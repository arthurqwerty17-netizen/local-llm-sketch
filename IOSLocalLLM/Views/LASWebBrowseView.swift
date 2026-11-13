import SwiftUI
import UIKit

// MARK: - LASWebBrowseView
//
// The browsing surface. Ask a question or paste a link; the agent searches,
// opens pages on your network, follows the relevant same-site links, and shows
// every step as it happens so browsing is never a black box.
//
// Web Access must be allowed for the run to start — the mode switch here writes
// the same Web Access setting the Web Tool uses, so there is one place where
// "may this app touch the network" is answered.

struct LASWebBrowseView: View {

    @ObservedObject private var agent = BrowsingAgentService.shared
    @ObservedObject private var webTool = WebToolService.shared
    @ObservedObject private var reachability = NetworkReachability.shared
    @Environment(\.koduTheme) private var T

    @State private var query = ""
    @State private var control: BrowsingAgentService.Control = .automatic

    var body: some View {
        VStack(spacing: 0) {
            LASDetailHeader("Web") {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: LASDesignTokens.component) {
                    composer
                    runCard
                }
                .padding(.horizontal, LASDesignTokens.pageInset)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(LASPageBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.row) {
            LASBrandLockup(size: 34, showsSubtitle: true)

            Text("Browses the web on your network and folds what it reads into the next reply. Inference stays on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: LASDesignTokens.tight) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Ask a question or paste a link", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { startIfPossible() }

                if agent.isRunning {
                    Button {
                        agent.cancel()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(T.bad)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop browsing")
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: startIfPossible) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(canStart ? T.accentStrong : T.ink4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart)
                    .accessibilityLabel("Start browsing")
                }
            }
            .padding(.horizontal, LASDesignTokens.component)
            .frame(minHeight: 52)
            .glassSurface(.card, cornerRadius: 20)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(LASDesignTokens.hairline, lineWidth: 1)
            }

            HStack(spacing: LASDesignTokens.tight) {
                ForEach(BrowsingAgentService.Control.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { control = option }
                    } label: {
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                control == option ? T.accentSoft : Color.primary.opacity(0.045),
                                in: Capsule()
                            )
                            .foregroundStyle(control == option ? T.accentStrong : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(control == option ? [.isButton, .isSelected] : .isButton)
                }

                Spacer(minLength: 0)

                Text(reachability.interfaceLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let note = accessNote {
                HStack(spacing: LASDesignTokens.tight) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 13, weight: .semibold))
                    Text(note)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(T.warn)
            }

            Divider().overlay(T.rule)

            // The single place "may this app touch the network" is answered.
            // Same setting the assistant's web tools read.
            HStack(spacing: LASDesignTokens.tight) {
                Text("WEB ACCESS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Menu {
                    ForEach(WebAccessMode.allCases) { mode in
                        Button {
                            webTool.settings.mode = mode
                        } label: {
                            if webTool.settings.mode == mode {
                                Label(accessTitle(mode), systemImage: "checkmark")
                            } else {
                                Text(accessTitle(mode))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(accessTitle(webTool.settings.mode))
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(T.accentStrong)
                }
                .accessibilityLabel("Web access mode")
            }
        }
        .lasCard()
    }

    private func accessTitle(_ mode: WebAccessMode) -> String {
        switch mode {
        case .off:           return "Off"
        case .askEveryTime:  return "Ask"
        case .alwaysAllow:   return "Always allow"
        }
    }

    private var canStart: Bool {
        webTool.settings.mode != .off && !agent.isRunning
    }

    private var accessNote: String? {
        if webTool.settings.mode == .off {
            return "Web Access is off. Turn it on below to browse."
        }
        if !webTool.settings.allowOnCellular, !reachability.isOnWiFi {
            return "Wi-Fi only is on and you are on cellular."
        }
        if control == .model, !AgentModelBridge.shared.hasBackend {
            return "Model-driven control needs a wired model backend; runs fall back to Automatic."
        }
        return nil
    }

    private func startIfPossible() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let goal: BrowsingAgentService.Goal = {
            if let url = URL(string: trimmed),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https",
               url.host != nil {
                return .url(url)
            }
            return .question(trimmed)
        }()
        agent.start(goal: goal, control: control)
    }

    // MARK: - Run

    @ViewBuilder
    private var runCard: some View {
        if let run = agent.current ?? agent.lastFinished {
            VStack(alignment: .leading, spacing: LASDesignTokens.row) {
                LASSectionLabel(
                    title: "RUN",
                    trailing: agent.isRunning ? "BROWSING" : (run.failure == nil ? "DONE" : "STOPPED"),
                    trailingColor: agent.isRunning ? T.accentStrong : (run.failure == nil ? T.good : T.warn)
                )

                Text(run.goal.displayText)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(run.steps) { step in
                    stepRow(step)
                }

                if !run.citations.isEmpty {
                    Divider().overlay(T.rule)
                    LASSectionLabel(title: "SOURCES", trailing: "\(run.citations.count)")
                    ForEach(run.citations) { citation in
                        HStack(alignment: .firstTextBaseline, spacing: LASDesignTokens.tight) {
                            Text("[\(citation.index)]")
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(T.accentStrong)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(citation.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                Text(citation.siteName)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Link(destination: citation.url) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .accessibilityLabel("Open \(citation.title)")
                        }
                    }
                }

                if let failure = run.failure {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(T.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let answer = run.answer, !answer.isEmpty {
                    Divider().overlay(T.rule)
                    LASSectionLabel(title: "ANSWER")
                    Text(answer)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !run.evidenceBlock.isEmpty {
                    Button {
                        UIPasteboard.general.string = run.evidenceBlock
                    } label: {
                        Label("Copy evidence to the chat", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LASSecondaryButtonStyle())
                }
            }
            .lasCard()
        }
    }

    private func stepRow(_ step: BrowsingAgentService.Step) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LASDesignTokens.tight) {
            Image(systemName: step.kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color(for: step.kind))
                .frame(width: 18)

            Text(step.kind.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(color(for: step.kind))
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.caption)
                    .lineLimit(2)
                if let detail = step.detail {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func color(for kind: BrowsingAgentService.StepKind) -> Color {
        switch kind {
        case .failed, .blocked: return T.warn
        case .finish:           return T.good
        case .answer:           return T.accentStrong
        default:                return T.ink3
        }
    }
}
