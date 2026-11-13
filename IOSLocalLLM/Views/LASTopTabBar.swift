import SwiftUI

// MARK: - LASTopTabs
//
// The shelf at the top of the screen: Chat and Files, with the browser as a
// third stop because the user thinks of it as "where the AI is". A segmented
// control rather than a tab bar so the app keeps its single-stack navigation and
// the header stays where it is.

enum LASTopTab: String, CaseIterable, Identifiable {
    case chat
    case browser
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:    return "Chat"
        case .browser: return "Web"
        case .files:   return "Files"
        }
    }

    var symbol: String {
        switch self {
        case .chat:    return "bubble.left.and.bubble.right"
        case .browser: return "globe"
        case .files:   return "folder"
        }
    }
}

// MARK: - TabRouter
//
// Which top tab is showing, held outside the view so non-UI code can bring the
// browser forward. When the assistant drives the browser the user should be
// looking at it, otherwise "watching the AI work" means nothing.

@MainActor
final class TabRouter: ObservableObject {
    static let shared = TabRouter()
    @Published var selection: LASTopTab = .chat
    private init() {}

    /// Bring a tab forward. Used by the browser tools after they act.
    func show(_ tab: LASTopTab) {
        guard selection != tab else { return }
        selection = tab
    }
}

struct LASTopTabBar: View {

    @ObservedObject private var router = TabRouter.shared
    @ObservedObject private var feed = BrowserActivityFeed.shared
    @Environment(\.koduTheme) private var T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LASTopTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { router.selection = tab }
                    HapticManager.impact(.light)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                        // Live dot: the assistant is driving the browser.
                        if tab == .browser, feed.isActive {
                            Circle()
                                .fill(T.accentStrong)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(
                        router.selection == tab ? T.accentSoft : Color.clear,
                        in: Capsule()
                    )
                    .foregroundStyle(router.selection == tab ? T.accentStrong : .secondary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(router.selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.045), in: Capsule())
        .overlay {
            Capsule().stroke(LASDesignTokens.hairline, lineWidth: 1)
        }
        .padding(.horizontal, LASDesignTokens.pageInset)
        .padding(.bottom, LASDesignTokens.tight)
    }
}
