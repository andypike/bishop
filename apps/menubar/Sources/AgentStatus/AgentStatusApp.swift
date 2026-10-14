import AppKit
import SwiftUI

/// `AgentStatus --print [--root <dir>]` prints the current view as text and
/// exits, for checking what the app would show; otherwise it runs the app.
@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--print") {
            printState(root: root(from: arguments))
        } else {
            AgentStatusApp.main()
        }
    }

    static func root(from arguments: [String]) -> URL {
        if let index = arguments.firstIndex(of: "--root"), index + 1 < arguments.count {
            return URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bishop")
    }

    static func printState(root: URL) {
        let now = Date()
        let projects = StateReader.read(root: root, now: now)
        let overall = projects.map(\.health).max() ?? .grey
        print("overall: \(overall)")
        for project in projects {
            let age = project.statusUpdated.map { StateReader.ago(now.timeIntervalSince($0)) } ?? "-"
            print("\n\(project.name) [\(project.health)] loop=\(project.loop ?? "-") ticked=\(age) stale=\(project.stale)")
            for ticket in project.tickets {
                let progress = ticket.progress.map { "\(Int($0.fraction * 100))% \($0.stage)" } ?? "-"
                print("  \(ticket.ticket) [\(ticket.health)] \(ticket.reason) | \(progress) | \(ticket.summary ?? "-")")
                print("      linear: \(ticket.url?.absoluteString ?? "-")  pr: \(ticket.prURL?.absoluteString ?? "-")")
            }
        }
    }
}

struct AgentStatusApp: App {
    @StateObject private var store = Store(root: Entry.root(from: CommandLine.arguments))

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(store)
        } label: {
            Image(nsImage: StatusIcon.image(health: store.health, count: store.needsYou))
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon: a dot in the overall colour, plus how many tickets need you.
enum StatusIcon {
    static func image(health: Health, count: Int) -> NSImage {
        let text = count > 0 ? NSAttributedString(
            string: "\(count)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]) : nil
        let dot: CGFloat = 10
        let gap: CGFloat = 4
        let textWidth = ceil(text?.size().width ?? 0)
        let size = NSSize(width: dot + (text == nil ? 0 : gap + textWidth), height: 16)

        let image = NSImage(size: size, flipped: false) { _ in
            health.nsColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: (16 - dot) / 2, width: dot, height: dot)).fill()
            if let text {
                text.draw(at: NSPoint(x: dot + gap, y: (16 - text.size().height) / 2))
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
