import Foundation
import Combine

// MARK: - BrowserActivityFeed
//
// Live, on-screen record of what the assistant is doing in the browser. Every
// browser-driving tool call appends a step here, and the Web tab renders the
// feed so the user watches the agent work instead of guessing.
//
// This is a view of the agent's own actions, not a screenshot: each step is the
// real URL, the real title, and the real outcome.

@MainActor
final class BrowserActivityFeed: ObservableObject {

    static let shared = BrowserActivityFeed()

    enum Kind: String, Sendable {
        case navigate, read, desktop, download, done, failed

        var symbol: String {
            switch self {
            case .navigate: return "arrow.up.right.square"
            case .read:     return "doc.text.magnifyingglass"
            case .desktop:  return "desktopcomputer"
            case .download: return "arrow.down.circle"
            case .done:     return "checkmark.circle.fill"
            case .failed:   return "exclamationmark.triangle.fill"
            }
        }

        var label: String {
            switch self {
            case .navigate: return "NAVIGATE"
            case .read:     return "READ"
            case .desktop:  return "DESKTOP"
            case .download: return "DOWNLOAD"
            case .done:     return "DONE"
            case .failed:   return "FAILED"
            }
        }
    }

    struct Step: Identifiable, Sendable {
        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String?
        let at: Date
    }

    @Published private(set) var steps: [Step] = []
    @Published private(set) var isActive = false
    @Published private(set) var statusLine: String = ""

    private var activeCount = 0

    private init() {}

    // MARK: - Recording

    /// Opens an activity. `begin`/`end` nest so a multi-page run stays "live"
    /// until its last step lands.
    func begin(_ kind: Kind, _ title: String, detail: String? = nil) {
        activeCount += 1
        isActive = true
        statusLine = title
        append(Step(kind: kind, title: title, detail: detail, at: Date()))
    }

    func end(_ kind: Kind, _ title: String, detail: String? = nil) {
        activeCount = max(0, activeCount - 1)
        isActive = activeCount > 0
        statusLine = title
        append(Step(kind: kind, title: title, detail: detail, at: Date()))
    }

    /// One-shot step that does not change the live indicator (used for reads).
    func note(_ kind: Kind, _ title: String, detail: String? = nil) {
        append(Step(kind: kind, title: title, detail: detail, at: Date()))
    }

    func clear() {
        steps.removeAll()
        statusLine = ""
        isActive = false
        activeCount = 0
    }

    private func append(_ step: Step) {
        steps.append(step)
        if steps.count > 60 {
            steps.removeFirst(steps.count - 60)
        }
    }
}
