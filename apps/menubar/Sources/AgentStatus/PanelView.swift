import AppKit
import ServiceManagement
import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var store: Store
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.projects.isEmpty {
                Text("No agents to show.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else if store.projects.flatMap(\.tickets).count > 5 {
                ScrollView { projectList }
                    .frame(height: 460)
            } else {
                projectList
            }
            Divider()
            FooterView()
        }
        .frame(width: 400)
    }

    private var header: some View {
        HStack {
            Text("Agents").font(.headline)
            Spacer()
            Text("\(store.needsYou) need you · \(store.running) running")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(store.projects) { project in
                ProjectSection(project: project, now: store.updated, expanded: $expanded)
            }
        }
        .padding(12)
    }
}

struct ProjectSection: View {
    let project: ProjectState
    let now: Date
    @Binding var expanded: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let url = project.url {
                    Link(project.name, destination: url).font(.subheadline.weight(.semibold))
                } else {
                    Text(project.name).font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(loopText)
                    .font(.caption)
                    .foregroundStyle(project.stale ? Health.amber.color : .secondary)
            }
            if project.tickets.isEmpty {
                Text("No agents working.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(project.tickets) { ticket in
                TicketRow(ticket: ticket, now: now, isExpanded: expanded.contains(ticket.id)) {
                    if expanded.contains(ticket.id) {
                        expanded.remove(ticket.id)
                    } else {
                        expanded.insert(ticket.id)
                    }
                }
            }
        }
    }

    private var loopText: String {
        let running = "running \(project.running)/\(project.maxWorkers.map(String.init) ?? "?")"
        let age = project.statusUpdated.map { StateReader.ago(now.timeIntervalSince($0)) }
        switch project.loop {
        case "paused":
            let until = project.pausedUntil.map { $0.formatted(date: .omitted, time: .shortened) } ?? "?"
            return "Usage limit — paused until \(until)"
        case "finished":
            return "Finished"
        case "running" where project.stale:
            return "No tick for \(age ?? "a while")"
        case "running":
            return "\(running) · ticked \(age ?? "?") ago"
        default:
            return running
        }
    }
}

struct TicketRow: View {
    let ticket: TicketState
    let now: Date
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(ticket.health.color)
                    .frame(width: 8, height: 8)
                ticketLink
                Text(ticket.title ?? "")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let activity = ticket.lastActivity {
                    Text(StateReader.ago(now.timeIntervalSince(activity)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ticket.reason)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ticket.health == .red || ticket.health == .amber ? ticket.health.color : .secondary)
                if let summary = ticket.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let progress = ticket.progress {
                    HStack(spacing: 8) {
                        ProgressView(value: progress.fraction)
                            .progressViewStyle(.linear)
                            .tint(ticket.health == .grey ? .accentColor : ticket.health.color)
                        Text(progress.stage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                links
                if isExpanded { details }
            }
            .padding(.leading, 16)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    @ViewBuilder private var ticketLink: some View {
        let label = Text(ticket.ticket).font(.system(.body, design: .monospaced).weight(.semibold))
        if let url = ticket.url {
            Link(destination: url) { label }
                .help("Open \(ticket.ticket) in Linear")
        } else {
            label
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(ticket.recentLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let worktree = ticket.worktree {
                Button("Open worktree") { NSWorkspace.shared.open(worktree) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 4)
    }

    /// Links that open in the browser: the Linear ticket, and the PR once there is one.
    private var links: some View {
        HStack(spacing: 14) {
            if let url = ticket.url {
                Link(destination: url) {
                    Label("Open in Linear", systemImage: "arrow.up.right.square")
                }
            }
            if let pr = ticket.prURL {
                Link(destination: pr) {
                    Label(prLabel(pr), systemImage: "arrow.triangle.pull")
                }
                .help(pr.absoluteString)
            }
        }
        .font(.caption)
        .padding(.top, 2)
    }

    /// "acme/shop#9" for a GitHub PR, otherwise the URL without its scheme.
    private func prLabel(_ url: URL) -> String {
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count >= 4, parts[2] == "pull" {
            return "\(parts[0])/\(parts[1])#\(parts[3])"
        }
        return (url.host ?? "") + url.path
    }
}

struct FooterView: View {
    @EnvironmentObject private var store: Store
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack {
            Toggle("Open at login", isOn: $openAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: openAtLogin) { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Spacer()
            Text("Updated \(store.updated.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button("Refresh") { store.refresh() }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
