import Foundation

/// Holds the current view of every project, refreshed when files under the
/// state directory change and every 15 seconds (ages and pids change without
/// any file changing). Notifies when a ticket turns red or a worker goes quiet.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var projects: [ProjectState] = []
    @Published private(set) var updated = Date()

    let root: URL
    private let notifier = Notifier()
    private var watcher: FileWatcher?
    private var timer: Timer?
    private var previous: [String: (Health, String)]?

    init(root: URL) {
        self.root = root
        refresh()
        watcher = FileWatcher(path: root.path) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var health: Health { projects.map(\.health).max() ?? .grey }

    var needsYou: Int { projects.flatMap(\.tickets).filter { $0.health == .red }.count }

    var running: Int { projects.map(\.running).reduce(0, +) }

    func refresh() {
        if watcher == nil, FileManager.default.fileExists(atPath: root.path) {
            // ~/.bishop didn't exist at launch; start watching now it does.
            watcher = FileWatcher(path: root.path) { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        }
        let now = Date()
        let next = StateReader.read(root: root, now: now)
        notifyChanges(next, now: now)
        projects = next
        updated = now
    }

    /// Compares with the last refresh; the first refresh only records, so
    /// launching the app doesn't replay everything already waiting.
    private func notifyChanges(_ next: [ProjectState], now: Date) {
        var current: [String: (Health, String)] = [:]
        for project in next {
            if project.stale { current[project.id + "#orchestrator"] = (.amber, "stale") }
            for ticket in project.tickets { current[ticket.id] = (ticket.health, ticket.reason) }
        }
        defer { previous = current }
        guard let previous else { return }

        for project in next {
            if project.stale && previous[project.id + "#orchestrator"] == nil {
                let age = project.statusUpdated.map { StateReader.ago(now.timeIntervalSince($0)) } ?? "a while"
                notifier.post(
                    title: "Orchestrator has stopped ticking",
                    body: "\(project.name): no update for \(age). Is its session still open?",
                    url: project.url)
            }
            for ticket in project.tickets {
                let before = previous[ticket.id]
                let title = ticket.title.map { " — \($0)" } ?? ""
                if ticket.health == .red && (before?.0 != .red || before?.1 != ticket.reason) {
                    notifier.post(
                        title: "\(ticket.ticket) needs you: \(ticket.reason)",
                        body: (ticket.summary ?? "") + title,
                        url: ticket.reason == "PR to review" ? (ticket.prURL ?? ticket.url) : ticket.url)
                } else if ticket.health == .amber && before?.0 != .amber {
                    notifier.post(
                        title: "\(ticket.ticket) has gone quiet",
                        body: "No progress logged for \(Int(StateReader.quietAfter / 60)) minutes"
                            + (ticket.summary.map { ". Last: \($0)" } ?? ""),
                        url: ticket.url)
                }
            }
        }
    }
}
