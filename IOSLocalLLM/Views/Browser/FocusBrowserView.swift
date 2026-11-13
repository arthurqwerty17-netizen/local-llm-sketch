import SwiftUI
import WebKit
import UIKit

// MARK: - FocusBrowserView
//
// The browser surface, laid out like the app it borrows its engine from: an
// address bar with the shield, a page area, and a bottom control bar. Extra
// here: the Desktop button, the AI panel that reads the current page, and the
// download indicator that points at the Files shelf.

struct FocusBrowserView: View {

    @ObservedObject private var browser = FocusBrowser.shared
    @ObservedObject private var files = WorkspaceFileStore.shared
    @ObservedObject private var agent = BrowsingAgentService.shared
    @ObservedObject private var feed = BrowserActivityFeed.shared
    @Environment(\.koduTheme) private var T

    @State private var editingAddress = false
    @State private var showingAI = false
    @State private var showingActivity = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            progressBar
            activityStrip
            page
            controlBar
        }
        .background(LASPageBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAI) {
            BrowserAIPanel().lasTheme()
        }
        .onChange(of: browser.addressText) { _, _ in
            editingAddress = addressFocused
        }
    }

    // MARK: - Address bar

    private var addressBar: some View {
        HStack(spacing: LASDesignTokens.tight) {
            HStack(spacing: 6) {
                Image(systemName: browser.currentURL?.scheme == "https"
                      ? "lock.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                TextField("Search or enter address", text: $browser.addressText)
                    .font(.subheadline)
                    .focused($addressFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit {
                        browser.navigate(to: browser.addressText)
                        addressFocused = false
                    }
                    .onChange(of: addressFocused) { _, focused in
                        browser.addressTextIsBeingEdited = focused
                    }

                if browser.isLoading {
                    Button { browser.stop() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if !browser.addressText.isEmpty {
                    Button { browser.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .overlay {
                Capsule().stroke(LASDesignTokens.hairline, lineWidth: 1)
            }

            // Desktop mode
            Button {
                browser.setDesktopMode(!browser.desktopMode)
                HapticManager.impact(.light)
            } label: {
                Image(systemName: browser.desktopMode ? "desktopcomputer" : "iphone")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(
                        browser.desktopMode ? T.accentSoft : Color.primary.opacity(0.05),
                        in: Circle()
                    )
                    .foregroundStyle(browser.desktopMode ? T.accentStrong : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(browser.desktopMode ? "Desktop mode on" : "Desktop mode off")
            .accessibilityAddTraits(browser.desktopMode ? [.isButton, .isSelected] : .isButton)
        }
        .padding(.horizontal, LASDesignTokens.pageInset)
        .padding(.top, LASDesignTokens.tight)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(T.accentStrong)
                .frame(width: proxy.size.width * browser.progress, height: 2)
                .opacity(browser.isLoading ? 1 : 0)
        }
        .frame(height: 2)
        .padding(.top, 4)
    }

    // MARK: - AI activity
    //
    // The live trace of what the assistant is doing in this browser. It sits
    // under the address bar so the user watches the agent rather than a spinner:
    // each line is a real action (URL opened, page read, file downloaded).

    @ViewBuilder
    private var activityStrip: some View {
        if feed.isActive || !feed.steps.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showingActivity.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        if feed.isActive {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(T.good)
                        }
                        Text(feed.isActive ? "AI is browsing" : "AI finished browsing")
                            .font(.caption2.weight(.semibold))
                        Text(feed.statusLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(feed.steps.count)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Image(systemName: showingActivity ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, LASDesignTokens.pageInset)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showingActivity {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(feed.steps.suffix(12)) { step in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: step.kind.symbol)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12)
                                Text(step.kind.label)
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(T.accentStrong)
                                    .frame(width: 54, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(step.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                    if let detail = step.detail {
                                        Text(detail)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, LASDesignTokens.pageInset)
                    .padding(.bottom, 8)
                }
            }
            .background(.ultraThinMaterial.opacity(0.5))
            .overlay(alignment: .bottom) {
                Rectangle().fill(LASDesignTokens.hairline).frame(height: 1)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Page

    private var page: some View {
        ZStack(alignment: .bottomTrailing) {
            BrowserWebView(browser: browser)
                // Rebuild once when the tracker blocklist finishes compiling, so
                // the rule list is in the web view's configuration from the start.
                .id(browser.blocklistVersion)

            if browser.currentURL == nil {
                emptyState
            }

            // Download notice pointing at the Files tab.
            if let name = browser.lastDownloadName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13))
                    Text(name)
                        .font(.caption2)
                        .lineLimit(1)
                    Text("saved to Files")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.trailing, LASDesignTokens.component)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: LASDesignTokens.row) {
            Image(systemName: "globe")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("Search, or paste a link")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: LASDesignTokens.tight) {
                ForEach(["github.com", "wikipedia.org", "swift.org"], id: \.self) { host in
                    Button {
                        browser.navigate(to: "https://\(host)")
                    } label: {
                        Text(host)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(T.accentSoft, in: Capsule())
                            .foregroundStyle(T.accentStrong)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 0) {
            barButton("chevron.left", label: "Back", enabled: browser.canGoBack) {
                browser.goBack()
            }
            barButton("chevron.right", label: "Forward", enabled: browser.canGoForward) {
                browser.goForward()
            }
            barButton("square.and.arrow.up", label: "Share", enabled: browser.currentURL != nil) {
                if let url = browser.currentURL {
                    UIPasteboard.general.string = url.absoluteString
                    ToastCenter.shared.success("Link copied")
                }
            }
            barButton("sparkles", label: "Ask AI about this page", enabled: browser.currentURL != nil) {
                showingAI = true
            }
            barButton("folder", label: "Files", enabled: true) {
                files.refresh()
                ToastCenter.shared.success(
                    "Files",
                    detail: "\(files.entries.count) items on the shelf"
                )
            }
        }
        .padding(.horizontal, LASDesignTokens.tight)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(LASDesignTokens.hairline).frame(height: 1)
        }
    }

    private func barButton(
        _ symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .accessibilityLabel(label)
    }
}

// MARK: - BrowserWebView

/// The WKWebView itself. Owns nothing: the shared `FocusBrowser` keeps the state
/// so the AI panel and the address bar read the same truth.
struct BrowserWebView: UIViewRepresentable {

    @ObservedObject var browser: FocusBrowser

    func makeUIView(context: Context) -> WKWebView {
        // The configuration carries the tracker blocklist, so it is built by the
        // model rather than here. `WKWebViewConfiguration` is copied at init, so
        // this view is keyed on `blocklistVersion` and rebuilt once when the
        // rule list finishes compiling.
        let webView = WKWebView(frame: .zero, configuration: browser.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .onDrag
        browser.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {

        private let browser: FocusBrowser

        init(browser: FocusBrowser) {
            self.browser = browser
        }

        // Downloads: hand the file to the shelf instead of dropping it.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            let downloadable = ["zip", "pdf", "tar", "gz", "tgz", "dmg", "ipa",
                                "txt", "md", "json", "swift", "sh", "csv"]
            if downloadable.contains(url.pathExtension.lowercased()) {
                decisionHandler(.download)
                return
            }
            // Keep http(s) and about: in-app; the OS opens everything else.
            if ["http", "https", "about", "file", "data"].contains(scheme) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        // MARK: WKDownloadDelegate

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            completionHandler(WorkspaceFileStore.availableURL(for: suggestedFilename))
        }

        func downloadDidFinish(_ download: WKDownload) {
            Task { @MainActor in
                await WorkspaceFileStore.shared.refreshAfterDownload()
                if let newest = WorkspaceFileStore.shared.entries.first {
                    browser.noteDownload(named: newest.name)
                }
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            Task { @MainActor in
                ToastCenter.shared.error("Download failed", detail: error.localizedDescription)
            }
        }
    }
}
