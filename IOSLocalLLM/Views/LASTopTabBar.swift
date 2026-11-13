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

struct LASTopTabBar: View {

    @Binding var selection: LASTopTab
    @Environment(\.koduTheme) private var T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LASTopTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = tab }
                    HapticManager.impact(.light)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(
                        selection == tab ? T.accentSoft : Color.clear,
                        in: Capsule()
                    )
                    .foregroundStyle(selection == tab ? T.accentStrong : .secondary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
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
