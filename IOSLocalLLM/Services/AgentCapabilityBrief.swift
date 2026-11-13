import Foundation

// MARK: - AgentCapabilityBrief
//
// The single place the model learns what it can actually do here and how. The
// addendum is built from the live state (is a repository linked, is a page
// open, what is on the shelf) rather than a static paragraph, so the model is
// never told about a tool that is not wired.

@MainActor
enum AgentCapabilityBrief {

    /// Prepended to the tool addendum for every assistant turn.
    static func text() -> String {
        var lines: [String] = []
        lines.append("""
        YOU ARE RUNNING INSIDE LOCAL LLM SKETCH
        Everything below runs on this iPhone. You are not in a cloud sandbox.
        Only claim to have done something when a tool returned its result.
        """)

        // Browser
        if FocusBrowser.shared.currentURL != nil {
            lines.append("""
            BROWSER — a page is open: \(FocusBrowser.shared.pageTitle.isEmpty ? "(untitled)" : FocusBrowser.shared.pageTitle)
            • browser_read() returns the text of the page the user is looking at right now.
            • browser_navigate(url) opens a URL in that same tab.
            • browser_desktop_mode(true|false) switches the page between mobile and desktop layout.
            • browser_download(url) saves a file from the web onto the Files shelf.
            """)
        } else {
            lines.append("""
            BROWSER — nothing is open yet.
            • browser_navigate(url) opens a URL in the in-app browser; the user watches it there.
            • browser_download(url) saves a file straight to the Files shelf without opening it.
            """)
        }

        // Files
        let store = WorkspaceFileStore.shared
        lines.append("""
        FILES SHELF — \(store.entries.count) item(s), \(store.totalByteCount.formattedBytes) total.
        • files_list() lists them. files_read(name) returns a text file's contents.
        • files_write(name, text) creates or replaces a file; the user can open it immediately.
        • shell(command) runs a small audited shell: ls, cat, head, wc, grep, swift, sh, git.
          It is NOT a general shell: there is no fork/exec on iOS, so no compilers, no
          package managers, and no arbitrary binaries. `swift file.swift` runs structural
          checks and reports that compilation needs CI.
        """)

        // GitHub
        let git = GitService.shared
        if git.hasToken {
            let repo = git.linkedRepository?.fullName ?? "(none linked)"
            lines.append("""
            GITHUB — linked to \(repo).
            • github_repo_files() lists the repository's tree.
            • github_read(path) reads a file from the repository.
            • github_commit(path, text, message) commits one file to the default branch.
            • github_build() dispatches the build-ipa workflow, which archives the app,
              uploads the IPA, and attaches it to a GitHub Release.
            • github_runs() reports the latest Actions runs.
            """)
        } else {
            lines.append("""
            GITHUB — not linked. Tell the user to paste a personal access token in
            GitHub settings (repo scope); you cannot ask for it yourself.
            """)
        }

        // Linux VM
        lines.append("""
        LINUX — there is no virtual machine. iOS enforces a hard rule against
        third-party JIT: no emulator, no hypervisor, no fork/exec, so no Arch,
        Debian, or any other distro can boot inside this app. Do not offer to
        "spin up Linux". If the user needs a shell, point them at the GitHub
        Actions job, which runs on a real Ubuntu runner, or at a paired Mac.
        """)

        // Team and look
        lines.append("""
        APPEARANCE — the user can pick an accent (Plum, Orchid, Lilac, Silver,
        Monochrome, Electric and more), a page canvas, and a light/dark/OLED
        appearance. Do not change these yourself; point at the paint palette
        in the header.
        """)

        return lines.joined(separator: "\n\n")
    }

    /// Live descriptions for the tool schema block, so the model's tool list and
    /// the actual ToolRunner dispatch never disagree.
    static let toolSchemas = """
      • browser_read()
          — text of the page the user is viewing in the in-app browser
      • browser_navigate(url: string)
          — open a URL in the in-app browser tab the user is looking at
      • browser_desktop_mode(enabled: bool)
          — switch the browser between mobile and desktop layout
      • browser_download(url: string, name?: string)
          — download a file to the Files shelf
      • files_list()
          — list the Files shelf
      • files_read(name: string)
          — read a text file from the shelf
      • files_write(name: string, text: string)
          — create or replace a file on the shelf
      • shell(command: string)
          — ls | cat <f> | head <f> [n] | wc <f> | grep <pat> [f…] | swift <f> | git <args>
      • github_repo_files()
          — list the linked repository's files
      • github_read(path: string)
          — read one file from the linked repository
      • github_commit(path: string, text: string, message: string)
          — commit one file to the linked repository
      • github_build()
          — dispatch the build-ipa workflow in Actions
      • github_runs()
          — latest Actions runs for the linked repository
    """
}
