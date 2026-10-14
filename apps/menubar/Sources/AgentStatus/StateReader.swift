import Foundation

/// The orchestrator's status.json, written every tick (see the orchestrate skill).
struct StatusFile: Decodable {
    struct Ticket: Decodable {
        let id: String
        let title: String?
        let url: String?
        let status: String?
        let label: String?
        let pr_url: String?
        let worktree: String?
    }

    let project: String?
    let project_url: String?
    let loop: String?
    let paused_until: String?
    let max_workers: Int?
    let tickets: [Ticket]?
}

/// Builds the view of every project and ticket from the files under ~/.bishop.
/// Read-only: it never writes a file or calls Linear.
enum StateReader {
    static let quietAfter: TimeInterval = 20 * 60
    static let staleAfter: TimeInterval = 15 * 60
    static let abandonedAfter: TimeInterval = 24 * 60 * 60

    static let parkedReasons = [
        "agent:awaiting-approval": "Plan to approve",
        "agent:needs-input": "Question to answer",
        "agent:gate-failed": "Quality gate failed",
        "agent:error": "Agent error",
        "agent:pr-open": "PR to review",
    ]

    static let finishedStatuses: Set<String> = ["QA", "Done", "Canceled"]

    static func read(root: URL, now: Date = Date()) -> [ProjectState] {
        var projects: [ProjectState] = []
        for repo in subdirectories(of: root) where repo.lastPathComponent != "worktrees" {
            for dir in subdirectories(of: repo) where dir.lastPathComponent != "worktrees" {
                if let project = readProject(dir, repo: repo.lastPathComponent, now: now) {
                    projects.append(project)
                }
            }
        }
        return projects.sorted {
            $0.health != $1.health ? $0.health > $1.health : $0.name < $1.name
        }
    }

    static func readProject(_ dir: URL, repo: String, now: Date) -> ProjectState? {
        let statusURL = dir.appendingPathComponent("status.json")
        let status = (try? Data(contentsOf: statusURL))
            .flatMap { try? JSONDecoder().decode(StatusFile.self, from: $0) }
        let statusUpdated = status == nil ? nil : modified(statusURL)

        var entries: [String: StatusFile.Ticket] = [:]
        for ticket in status?.tickets ?? [] { entries[ticket.id] = ticket }

        let ticketDirs = subdirectories(of: dir).filter { ticketDir in
            ["progress.md", "pid", "worker.md"].contains {
                FileManager.default.fileExists(atPath: ticketDir.appendingPathComponent($0).path)
            }
        }
        let ids = Set(ticketDirs.map(\.lastPathComponent)).union(entries.keys)

        // Ticket links come from status.json; for tickets it doesn't cover
        // (an orchestrator that predates it), build them from the workspace.
        let needsWorkspace = ids.contains { entries[$0]?.url == nil }
        let workspace = needsWorkspace ? linearWorkspace(in: ticketDirs) : nil

        var tickets: [TicketState] = []
        for id in ids {
            guard var ticket = readTicket(
                id, dir: dir.appendingPathComponent(id), entry: entries[id],
                statusUpdated: statusUpdated, hasStatusFile: status != nil, projectID: dir.path, now: now)
            else { continue }
            if ticket.url == nil, let workspace {
                ticket.url = URL(string: workspace + "issue/" + id)
            }
            tickets.append(ticket)
        }
        tickets.sort {
            $0.health != $1.health
                ? $0.health > $1.health
                : $0.ticket.localizedStandardCompare($1.ticket) == .orderedAscending
        }

        let age = statusUpdated.map { now.timeIntervalSince($0) }
        let stale = status?.loop == "running" && age.map { $0 > staleAfter && $0 < abandonedAfter } == true
        let active = (status?.loop == "running" || status?.loop == "paused") && age.map { $0 < abandonedAfter } == true
        guard !tickets.isEmpty || active else { return nil }

        return ProjectState(
            id: dir.path,
            name: status?.project ?? "\(repo) / \(dir.lastPathComponent)",
            url: status?.project_url.flatMap(URL.init(string:)),
            loop: status?.loop,
            pausedUntil: status?.paused_until.flatMap { ISO8601DateFormatter().date(from: $0) },
            maxWorkers: status?.max_workers,
            statusUpdated: statusUpdated,
            stale: stale,
            tickets: tickets)
    }

    static func readTicket(
        _ ticket: String, dir: URL, entry: StatusFile.Ticket?, statusUpdated: Date?,
        hasStatusFile: Bool, projectID: String, now: Date
    ) -> TicketState? {
        let progressURL = dir.appendingPathComponent("progress.md")
        let lines = ((try? String(contentsOf: progressURL, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        let lastActivity = lines.isEmpty ? nil : modified(progressURL)
        let process = processState(dir.appendingPathComponent("pid"))
        let last = lines.last

        // Hide what the orchestrator has finished with.
        if process == .none {
            if let entry {
                if entry.label == nil && finishedStatuses.contains(entry.status ?? "") { return nil }
            } else if hasStatusFile || last == nil || last?.contains("· Cleaned up") == true {
                // Not tracked by the orchestrator, or from before progress logs.
                return nil
            }
        }

        // The current claim's lines: a Rejected ticket claimed again starts over.
        let start = lines.lastIndex { $0.contains("· Claimed") } ?? 0
        let run = Array(lines[start...])

        let (health, assessed) = assess(
            process: process, label: entry?.label, status: entry?.status, last: last,
            lastActivity: lastActivity, statusUpdated: statusUpdated, now: now)
        let reason = lines.isEmpty && process == .running ? "Starting" : assessed

        return TicketState(
            id: projectID + "/" + ticket,
            ticket: ticket,
            title: entry?.title,
            url: entry?.url.flatMap(URL.init(string:)),
            prURL: entry?.pr_url.flatMap(URL.init(string:)) ?? loggedPR(run),
            worktree: entry?.worktree.map { URL(fileURLWithPath: $0) },
            label: entry?.label,
            status: entry?.status,
            process: process,
            summary: last.map(withoutTime),
            lastActivity: lastActivity,
            recentLines: Array(run.suffix(5)),
            progress: progress(run),
            health: health,
            reason: reason)
    }

    static func assess(
        process: WorkerProcess, label: String?, status: String?, last: String?,
        lastActivity: Date?, statusUpdated: Date?, now: Date
    ) -> (Health, String) {
        if process == .running {
            guard let lastActivity else { return (.green, "Working") }
            let idle = now.timeIntervalSince(lastActivity)
            return idle > quietAfter ? (.amber, "Quiet for \(ago(idle))") : (.green, "Working")
        }

        // A worker that parked or opened its PR since the orchestrator's last
        // tick: trust its own log until the next status.json catches up.
        let logIsNewer = lastActivity.map { activity in statusUpdated.map { activity > $0 } ?? true } ?? false
        if logIsNewer, let last {
            if last.contains("· Parked ·") {
                let parkedLabel = last.components(separatedBy: " · ").first { $0.hasPrefix("agent:") }
                return (.red, parkedLabel.flatMap { parkedReasons[$0] } ?? "Needs you")
            }
            if last.contains("· PR opened") || last.contains("Merge conflicts · resolved") {
                return (.red, "PR to review")
            }
        }

        if let label, let reason = parkedReasons[label], !finishedStatuses.contains(status ?? "") {
            return (.red, reason)
        }

        switch label {
        case "agent:claimable": return (.grey, "Queued")
        case "agent:plan-approved", "agent:answered": return (.grey, "Resuming next tick")
        default: break
        }
        if process == .exited { return (.grey, "Stopped — waiting for the orchestrator") }
        return (.grey, status ?? "Idle")
    }

    /// Phases 1–4 fill the first 15%, the slices of Phase 5 the next 55%,
    /// and the quality gate, correctness check and wrap-up the rest.
    static func progress(_ run: [String]) -> StageProgress? {
        if run.contains(where: { $0.contains("· PR opened") }) {
            return StageProgress(fraction: 1, stage: "PR opened")
        }
        guard let phaseLine = run.last(where: { match(#"Phase (\d)"#, in: $0) != nil }),
            let phase = match(#"Phase (\d)"#, in: phaseLine).flatMap({ Int($0[0]) })
        else { return nil }

        switch phase {
        case 1...4:
            let fractions = [1: 0.02, 2: 0.05, 3: 0.10, 4: 0.14]
            return StageProgress(fraction: fractions[phase]!, stage: "Phase \(phase) · \(phaseNames[phase]!)")
        case 5:
            guard let sliceLine = run.last(where: { match(#"slice (\d+)/(\d+)"#, in: $0) != nil }),
                let numbers = match(#"slice (\d+)/(\d+)"#, in: sliceLine),
                let slice = Int(numbers[0]), let total = Int(numbers[1]), total > 0
            else { return StageProgress(fraction: 0.15, stage: "Phase 5 · Implementation") }
            let done = sliceLine.contains("committed") ? slice : slice - 1
            return StageProgress(
                fraction: 0.15 + 0.55 * Double(min(done, total)) / Double(total),
                stage: "Phase 5 · slice \(slice)/\(total)")
        default:
            let fractions = [6: 0.75, 7: 0.92, 8: 0.97]
            return StageProgress(
                fraction: fractions[phase] ?? 0.97, stage: "Phase \(phase) · \(phaseNames[phase] ?? "")")
        }
    }

    static let phaseNames = [
        1: "Intake", 2: "Investigation", 3: "Planning", 4: "Plan posted",
        5: "Implementation", 6: "Quality gate", 7: "Correctness check", 8: "Wrap-up",
    ]

    // MARK: - Helpers

    /// "https://linear.app/<workspace>/", from the first Linear link in a
    /// worker's PR body (which links its ticket).
    static func linearWorkspace(in ticketDirs: [URL]) -> String? {
        for dir in ticketDirs {
            guard let body = try? String(contentsOf: dir.appendingPathComponent("pr-body.md"), encoding: .utf8),
                let slug = match(#"https://linear\.app/([A-Za-z0-9_-]+)/"#, in: body)?.first
            else { continue }
            return "https://linear.app/\(slug)/"
        }
        return nil
    }

    /// The PR URL from the worker's `PR opened · <url>` line, before the
    /// orchestrator's status.json has caught up.
    static func loggedPR(_ run: [String]) -> URL? {
        guard let line = run.last(where: { $0.contains("· PR opened") }),
            let link = match(#"(https?://\S+)"#, in: line)?.first
        else { return nil }
        return URL(string: link)
    }

    static func withoutTime(_ line: String) -> String {
        guard let range = line.range(of: " · ") else { return line }
        return String(line[range.upperBound...])
    }

    static func ago(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h \(s % 3600 / 60)m" }
        return "\(s / 86400)d"
    }

    static func match(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<result.numberOfRanges).compactMap {
            Range(result.range(at: $0), in: text).map { String(text[$0]) }
        }
    }

    static func processState(_ pidFile: URL) -> WorkerProcess {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return .none }
        guard let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return .exited }
        return kill(pid, 0) == 0 || errno == EPERM ? .running : .exited
    }

    static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func subdirectories(of url: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
