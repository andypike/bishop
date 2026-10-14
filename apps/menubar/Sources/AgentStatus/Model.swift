import AppKit
import SwiftUI

/// How much a ticket, project, or the whole menu bar needs the developer.
/// Ordered so the most urgent wins when combined.
enum Health: Int, Comparable {
    case grey, green, amber, red

    static func < (lhs: Health, rhs: Health) -> Bool { lhs.rawValue < rhs.rawValue }

    var nsColor: NSColor {
        switch self {
        case .grey: return .systemGray
        case .green: return .systemGreen
        case .amber: return .systemOrange
        case .red: return .systemRed
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

enum WorkerProcess {
    case running
    case exited // pid file left behind; the orchestrator hasn't reaped it yet
    case none
}

/// An estimate of how far through the ticket-workflow phases a worker is.
struct StageProgress {
    var fraction: Double
    var stage: String
}

struct TicketState: Identifiable {
    let id: String // project path + ticket, unique across projects
    let ticket: String
    var title: String?
    var url: URL?
    var prURL: URL?
    var worktree: URL?
    var label: String?
    var status: String?
    var process: WorkerProcess
    var summary: String? // latest progress line, without its time
    var lastActivity: Date?
    var recentLines: [String]
    var progress: StageProgress?
    var health: Health
    var reason: String
}

struct ProjectState: Identifiable {
    let id: String // project state dir path
    var name: String
    var url: URL?
    var loop: String?
    var pausedUntil: Date?
    var maxWorkers: Int?
    var statusUpdated: Date?
    var stale: Bool
    var tickets: [TicketState]

    var running: Int { tickets.filter { $0.process == .running }.count }

    var health: Health {
        max(stale ? .amber : .grey, tickets.map(\.health).max() ?? .grey)
    }
}
