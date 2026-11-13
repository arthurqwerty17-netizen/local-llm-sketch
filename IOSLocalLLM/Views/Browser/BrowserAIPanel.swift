import SwiftUI

// MARK: - BrowserAIPanel
//
// "Ask about this page." Reads the page the user is viewing, hands it to the
// configured local model, and shows the answer. The page text is the only thing
// that leaves the browser, and it goes to the on-device runtime.
//
// Note on naming: the local LLM never touches the network. The browser fetched
// the page; this panel only reads what is already rendered.

struct BrowserAIPanel: View {

    @ObservedObject private var browser = FocusBrowser.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.koduTheme) private var T

    @State private var question = ""
    @State private var answer = ""
    @State private var isThinking = false
    @State private var pagePreview: String?
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            LASDetailHeader("Ask about this page") {
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: LASDesignTokens.component) {
                    pageCard
                    askCard
                    if !answer.isEmpty { answerCard }
                }
                .padding(.horizontal, LASDesignTokens.pageInset)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(LASPageBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadPreview() }
    }

    // MARK: - Page

    private var pageCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
            LASSectionLabel(
                title: "PAGE",
                trailing: browser.currentURL?.host?.uppercased() ?? "—"
            )
            Text(browser.pageTitle.isEmpty ? "Untitled" : browser.pageTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if let url = browser.currentURL {
                Text(url.absoluteString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let preview = pagePreview {
                Text(preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isThinking {
                Text("Reading the page…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .lasCard()
    }

    // MARK: - Ask

    private var askCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.row) {
            LASSectionLabel(title: "QUESTION")

            TextField("What should I look for?", text: $question, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            Button {
                Task { await ask() }
            } label: {
                HStack {
                    if isThinking {
                        ProgressView().controlSize(.small)
                    }
                    Text(isThinking ? "Thinking…" : "Ask the local model")
                    Spacer()
                    Image(systemName: "sparkles")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LASPrimaryButtonStyle())
            .disabled(isThinking || question.trimmingCharacters(in: .whitespaces).isEmpty)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(T.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The page text is read from the rendered page and passed to the model running on this device. Nothing is sent to a server by this panel.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lasCard()
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
            HStack {
                LASSectionLabel(title: "ANSWER")
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = answer
                    ToastCenter.shared.success("Answer copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text(answer)
                .font(.subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lasCard()
    }

    // MARK: - Work

    private func loadPreview() async {
        guard let text = await browser.visibleText(limit: 600) else { return }
        pagePreview = text
    }

    private func ask() async {
        guard let context = await browser.pageContextBlock() as String? else { return }
        isThinking = true
        errorText = nil
        defer { isThinking = false }

        let prompt = """
        \(context)

        QUESTION ABOUT THIS PAGE
        \(question)
        """

        guard AgentModelBridge.shared.hasBackend else {
            errorText = "Model-backed page answers are not wired in this build yet. The browser tools (reading, navigating, downloading) work from the Chat tab's assistant."
            return
        }
        guard let reply = await AgentModelBridge.shared.complete(prompt: prompt, maxTokens: 700) else {
            errorText = "The local model did not answer. Load a model from the Chat tab first."
            return
        }
        answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
