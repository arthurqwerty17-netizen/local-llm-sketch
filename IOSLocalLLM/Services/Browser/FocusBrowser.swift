import Foundation
import Combine
import WebKit
import UIKit

// MARK: - FocusBrowser
//
// The in-app browser. Same shape as the Focus Lite engine the user pointed at:
// a WKWebView with a content-rule tracker blocker, a small JS bridge that
// reports what the page is showing, a desktop-mode switch that changes the user
// agent and page scale, and downloads that land on the Files shelf.
//
// The AI reads the page through `visibleText()`, so "see what they're viewing"
// means the same thing here as it does for a human: the rendered text of the
// page in the current tab, never the network stream.

@MainActor
final class FocusBrowser: NSObject, ObservableObject {

    static let shared = FocusBrowser()

    // MARK: - Published state

    @Published var addressText: String = ""
    @Published private(set) var currentURL: URL?
    @Published private(set) var pageTitle: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var desktopMode: Bool = false
    @Published private(set) var blockedCount: Int = 0
    @Published private(set) var lastDownloadName: String?
    @Published private(set) var lastError: String?

    /// Set by the view so navigation can happen from anywhere (FAB, AI, links).
    weak var webView: WKWebView?

    private var observations: [NSKeyValueObservation] = []
    private var ruleList: WKContentRuleList?

    private override init() {
        super.init()
        loadRuleList()
    }

    // MARK: - Tracker blocking
    //
    // A content rule list is the only supported way to block requests in
    // WKWebView without a proxy. Kept short on purpose: a large list costs
    // startup time and this app's browser is a research surface, not an
    // ad-funded browsing session.

    private func loadRuleList() {
        let blockedHosts = [
            "doubleclick.net", "googlesyndication.com", "google-analytics.com",
            "googletagmanager.com", "adservice.google.com", "facebook.net",
            "connect.facebook.net", "scorecardresearch.com", "criteo.com",
            "criteo.net", "taboola.com", "outbrain.com", "hotjar.com",
            "segment.io", "mixpanel.com", "amplitude.com", "quantserve.com",
            "adnxs.com", "rubiconproject.com", "pubmatic.com", "openx.net",
            "moatads.com", "zedo.com", "adform.net", "smartadserver.com",
            "popads.net", "propellerads.com", "onclickads.net"
        ]
        let rules: [[String: Any]] = blockedHosts.map { host in
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*\(host)"]],
                "action": ["type": "block"]
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "FocusBrowserBlocklist",
            encodedContentRuleList: json
        ) { [weak self] list, _ in
            Task { @MainActor in
                self?.ruleList = list
                self?.applyRuleList()
            }
        }
    }

    private func applyRuleList() {
        guard let webView, let ruleList else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        controller.add(ruleList)
    }

    // MARK: - Wiring

    /// Attaches the live web view. The view calls this once per view instance.
    func attach(_ webView: WKWebView) {
        self.webView = webView
        if let ruleList {
            webView.configuration.userContentController.add(ruleList)
        }
        applyDesktopMode()

        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.currentURL = view.url
                    if let url = view.url, !self.addressTextIsBeingEdited {
                        self.addressText = url.absoluteString
                    }
                }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                let title = view.title ?? ""
                Task { @MainActor in self?.pageTitle = title }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                let loading = view.isLoading
                Task { @MainActor in self?.isLoading = loading }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                let value = view.estimatedProgress
                Task { @MainActor in self?.progress = value }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                let value = view.canGoBack
                Task { @MainActor in self?.canGoBack = value }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                let value = view.canGoForward
                Task { @MainActor in self?.canGoForward = value }
            }
        ]
    }

    /// Set while the user is typing so the address field is not rewritten.
    var addressTextIsBeingEdited = false

    // MARK: - Navigation

    /// Resolves bare input the way a browser does: a URL when it looks like
    /// one, otherwise a search. `nil` input returns to a blank page.
    func navigate(to raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let url = Self.resolve(trimmed) else { return }
        load(url)
    }

    func load(_ url: URL) {
        guard let webView else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        webView.load(request)
        currentURL = url
        addressText = url.absoluteString
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stop() { webView?.stopLoading() }

    func setDesktopMode(_ enabled: Bool) {
        desktopMode = enabled
        applyDesktopMode()
        webView?.reload()
    }

    private func applyDesktopMode() {
        guard let webView else { return }
        if desktopMode {
            webView.customUserAgent = Self.desktopUserAgent
        } else {
            webView.customUserAgent = nil
        }
    }

    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            return url
        }
        // Bare domain ("example.com", "example.com/path", "192.168.1.1").
        let looksLikeDomain = trimmed.contains(".")
            && !trimmed.contains(" ")
            && trimmed.first != "."
        if looksLikeDomain {
            return URL(string: "https://\(trimmed)")
        }
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    // MARK: - Reading the page for the AI

    /// The rendered text of the current page, capped so it fits a prompt.
    /// This is what "the model can see what you are viewing" means: the same
    /// text a person would read, taken from the live DOM.
    func visibleText(limit: Int = 8_000) async -> String? {
        guard let webView else { return nil }
        let script = """
        (function () {
          var pick = document.querySelector('article, main, [role=main]') || document.body;
          if (!pick) return '';
          var text = pick.innerText || pick.textContent || '';
          return text.replace(/\\s+\\n/g, '\\n').replace(/\\n{3,}/g, '\\n\\n').trim();
        })();
        """
        let value = try? await webView.evaluateJavaScript(script)
        guard let text = value as? String, !text.isEmpty else { return nil }
        return String(text.prefix(limit))
    }

    /// A labelled block the prompt builder can drop straight into a message.
    func pageContextBlock() async -> String {
        guard let url = currentURL else { return "" }
        let body = await visibleText() ?? "(the page produced no readable text)"
        return """
        THE USER IS VIEWING THIS PAGE IN THE IN-APP BROWSER
        Title: \(pageTitle.isEmpty ? "(untitled)" : pageTitle)
        URL: \(url.absoluteString)

        \(body)
        """
    }

    // MARK: - Downloads
    //
    // WKDownload is driven entirely by the view's navigation delegate, which
    // writes into `WorkspaceFileStore.directoryURL` and then calls
    // `refreshAfterDownload()`. The browser itself only reports the newest file.

    /// Records that a download landed, for the in-view notice.
    func noteDownload(named name: String) {
        lastDownloadName = name
    }
}
