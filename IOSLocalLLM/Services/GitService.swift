import Foundation
import Combine

// MARK: - GitFailure

/// A GitHub failure carrying a message the UI can show.
///
/// `Result` requires its failure type to conform to `Error`, and a bare
/// `String` does not, so every `Result<…, String>` here was a compile error.
struct GitFailure: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

// MARK: - GitService
//
// GitHub access for the assistant. Two halves:
//
//  • REST, with the user's own token: list repos, read a file, list a branch,
//    check runs, dispatch a workflow, and read a release. This is what "make
//    changes based on my repo" actually needs: read the real source, then write
//    a patch or dispatch CI.
//  • Local git, against a checkout the app owns, through `WorkspaceShell.git`.
//    iOS has no git binary, so the local half is limited to reading a checked
//    out tree that was downloaded as an archive — committing and pushing go
//    through the REST API (contents/blobs/trees/commits), not a local git.
//
// The token lives in the Keychain via KeychainStore, never in AppSettings.

@MainActor
final class GitService: ObservableObject {

    static let shared = GitService()

    // MARK: - Types

    struct Repository: Identifiable, Hashable, Sendable {
        let id: Int
        let fullName: String
        let name: String
        let owner: String
        let isPrivate: Bool
        let defaultBranch: String
        let htmlURL: URL?

        var slug: String { fullName }
    }

    struct WorkflowRun: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let status: String
        let conclusion: String?
        let branch: String
        let htmlURL: URL?
        let createdAt: Date?
    }

    struct ReleaseInfo: Identifiable, Hashable, Sendable {
        let id: Int
        let tagName: String
        let name: String
        let htmlURL: URL?
        let assetNames: [String]
        let publishedAt: Date?
    }

    struct FileEntry: Identifiable, Hashable, Sendable {
        let path: String
        let sha: String
        let size: Int

        var id: String { path }
    }

    // MARK: - Published

    @Published private(set) var repositories: [Repository] = []
    @Published private(set) var runs: [WorkflowRun] = []
    @Published private(set) var releases: [ReleaseInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var accountLogin: String?

    /// The repository the app is linked to. The agent reads this one by default.
    @Published var linkedRepository: Repository?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28"
        ]
        return URLSession(configuration: config)
    }()

    private let tokenAccount = "github.token"
    private let linkKey = "github.linkedRepo"

    private init() {
        if let stored = UserDefaults.standard.string(forKey: linkKey) {
            let parts = stored.split(separator: "/")
            if parts.count == 2 {
                linkedRepository = Repository(
                    id: 0,
                    fullName: stored,
                    name: String(parts[1]),
                    owner: String(parts[0]),
                    isPrivate: true,
                    defaultBranch: "main",
                    htmlURL: URL(string: "https://github.com/\(stored)")
                )
            }
        }
    }

    // MARK: - Token

    var hasToken: Bool { KeychainStore.get(account: tokenAccount) != nil }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.set(trimmed, account: tokenAccount)
    }

    func clearToken() {
        KeychainStore.delete(account: tokenAccount)
        accountLogin = nil
        repositories = []
        linkedRepository = nil
        UserDefaults.standard.removeObject(forKey: linkKey)
    }

    private var token: String? { KeychainStore.get(account: tokenAccount) }

    func link(_ repository: Repository) {
        linkedRepository = repository
        UserDefaults.standard.set(repository.fullName, forKey: linkKey)
    }

    // MARK: - Requests

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async -> Result<Data, GitFailure> {
        guard let token else { return .failure(GitFailure("No GitHub token saved.")) }
        guard let url = URL(string: "https://api.github.com\(path)") else {
            return .failure(GitFailure("Bad GitHub path."))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await NetworkActivityMonitor.shared.track(label: "GitHub") {
                try await session.data(for: request)
            }
            guard let http = response as? HTTPURLResponse else {
                return .failure(GitFailure("GitHub returned a non-HTTP response."))
            }
            switch http.statusCode {
            case 200...299:
                return .success(data)
            case 401:
                return .failure(GitFailure("GitHub rejected the token. Check that it has repo scope."))
            case 403:
                return .failure(GitFailure("GitHub refused the request (rate limit or insufficient scope)."))
            case 404:
                return .failure(GitFailure("GitHub could not find that resource. Check the owner and repository name."))
            default:
                let text = String(data: data, encoding: .utf8) ?? ""
                return .failure(GitFailure("GitHub error \(http.statusCode): \(text.prefix(200))"))
            }
        } catch {
            return .failure(GitFailure(error.localizedDescription))
        }
    }

    // MARK: - Reads

    func loadAccount() async {
        isLoading = true
        defer { isLoading = false }
        guard case .success(let data) = await request("/user") else { return }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let login = object["login"] as? String {
            accountLogin = login
        }
    }

    func loadRepositories() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        guard case .success(let data) = await request(
            "/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member"
        ) else {
            if case .failure(let failure) = await request("/user/repos?per_page=1&sort=updated") {
                lastError = failure.message
            }
            return
        }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            lastError = "Could not read the repository list."
            return
        }
        repositories = array.compactMap { item in
            guard let id = item["id"] as? Int,
                  let fullName = item["full_name"] as? String,
                  let name = item["name"] as? String else { return nil }
            let owner = (item["owner"] as? [String: Any])?["login"] as? String
                ?? fullName.split(separator: "/").first.map(String.init) ?? ""
            return Repository(
                id: id,
                fullName: fullName,
                name: name,
                owner: owner,
                isPrivate: item["private"] as? Bool ?? true,
                defaultBranch: item["default_branch"] as? String ?? "main",
                htmlURL: (item["html_url"] as? String).flatMap(URL.init(string:))
            )
        }

        // Keep the stored link in sync with fresh metadata.
        if let current = linkedRepository,
           let fresh = repositories.first(where: { $0.fullName == current.fullName }) {
            linkedRepository = fresh
        }
    }

    /// The file list of a branch. Used to let the model see the real tree before
    /// it proposes a change.
    func listTree(repository: Repository, branch: String? = nil) async -> [FileEntry] {
        let ref = branch ?? repository.defaultBranch
        let path = "/repos/\(repository.fullName)/git/trees/\(ref)?recursive=1"
        guard case .success(let data) = await request(path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = object["tree"] as? [[String: Any]] else {
            return []
        }
        return tree.compactMap { node in
            guard (node["type"] as? String) == "blob",
                  let filePath = node["path"] as? String,
                  let sha = node["sha"] as? String else { return nil }
            return FileEntry(path: filePath, sha: sha, size: node["size"] as? Int ?? 0)
        }
    }

    func readFile(repository: Repository, path filePath: String, branch: String? = nil) async -> String? {
        let ref = branch ?? repository.defaultBranch
        let encoded = filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath
        guard case .success(let data) = await request(
            "/repos/\(repository.fullName)/contents/\(encoded)?ref=\(ref)"
        ) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? String,
              let decoded = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: ""))
        else { return nil }
        return String(data: decoded, encoding: .utf8)
    }

    /// Reads the file and saves it on the shelf, so the shell and the viewer can
    /// both use it after the model has looked at it.
    @discardableResult
    func downloadFileToShelf(
        repository: Repository,
        path filePath: String,
        branch: String? = nil
    ) async -> WorkspaceFileStore.Entry? {
        guard let text = await readFile(repository: repository, path: filePath, branch: branch) else {
            return nil
        }
        let name = "\(repository.name)-\(filePath.replacingOccurrences(of: "/", with: "-"))"
        return try? WorkspaceFileStore.shared.save(data: Data(text.utf8), name: name)
    }

    func loadRuns(repository: Repository) async {
        guard case .success(let data) = await request(
            "/repos/\(repository.fullName)/actions/runs?per_page=20"
        ) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["workflow_runs"] as? [[String: Any]] else { return }
        let formatter = ISO8601DateFormatter()
        runs = list.compactMap { run in
            guard let id = run["id"] as? Int else { return nil }
            return WorkflowRun(
                id: id,
                name: run["name"] as? String ?? "workflow",
                status: run["status"] as? String ?? "unknown",
                conclusion: run["conclusion"] as? String,
                branch: run["head_branch"] as? String ?? "",
                htmlURL: (run["html_url"] as? String).flatMap(URL.init(string:)),
                createdAt: (run["created_at"] as? String).flatMap { formatter.date(from: $0) }
            )
        }
    }

    func loadReleases(repository: Repository) async {
        guard case .success(let data) = await request(
            "/repos/\(repository.fullName)/releases?per_page=10"
        ) else { return }
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let formatter = ISO8601DateFormatter()
        releases = list.compactMap { release in
            guard let id = release["id"] as? Int,
                  let tag = release["tag_name"] as? String else { return nil }
            let assets = (release["assets"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
            return ReleaseInfo(
                id: id,
                tagName: tag,
                name: release["name"] as? String ?? tag,
                htmlURL: (release["html_url"] as? String).flatMap(URL.init(string:)),
                assetNames: assets,
                publishedAt: (release["published_at"] as? String).flatMap { formatter.date(from: $0) }
            )
        }
    }

    // MARK: - Writes

    /// Commits a single file to a branch through the contents API. This is the
    /// smallest write the API allows and it is enough for "make this change in
    /// my repo": one path, one message, one commit.
    func commitFile(
        repository: Repository,
        path filePath: String,
        contents: String,
        message: String,
        branch: String? = nil
    ) async -> Result<URL, GitFailure> {
        let ref = branch ?? repository.defaultBranch
        let encoded = filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath

        // Existing files need their blob sha to be replaced rather than created.
        var sha: String?
        if case .success(let data) = await request(
            "/repos/\(repository.fullName)/contents/\(encoded)?ref=\(ref)"
        ), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            sha = object["sha"] as? String
        }

        var payload: [String: Any] = [
            "message": message,
            "content": Data(contents.utf8).base64EncodedString(),
            "branch": ref
        ]
        if let sha { payload["sha"] = sha }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return .failure(GitFailure("Could not encode the commit."))
        }
        guard case .success(let data) = await request(
            "/repos/\(repository.fullName)/contents/\(encoded)",
            method: "PUT",
            body: body
        ) else {
            return .failure(GitFailure("GitHub rejected the commit."))
        }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let url = ((object?["commit"] as? [String: Any])?["html_url"] as? String)
            .flatMap(URL.init(string:))
        return .success(url ?? URL(string: "https://github.com/\(repository.fullName)")!)
    }

    /// Starts a workflow run. The companion `build-ipa.yml` in this repo is the
    /// target: it archives the app, uploads the IPA, and attaches it to a
    /// release, which is the "compile everything in Actions" path.
    func dispatchWorkflow(
        repository: Repository,
        workflowFile: String = "build-ipa.yml",
        ref: String? = nil
    ) async -> Result<String, GitFailure> {
        let body = try? JSONSerialization.data(withJSONObject: [
            "ref": ref ?? repository.defaultBranch
        ])
        let result = await request(
            "/repos/\(repository.fullName)/actions/workflows/\(workflowFile)/dispatches",
            method: "POST",
            body: body
        )
        switch result {
        case .success:
            return .success("Dispatched \(workflowFile) on \(ref ?? repository.defaultBranch).")
        case .failure(let failure):
            // 204 No Content is the documented success; a 404 usually means the
            // workflow file is not on the default branch yet.
            if failure.message.contains("404") {
                return .failure(GitFailure("That workflow is not on \(repository.defaultBranch) yet."))
            }
            return .failure(failure)
        }
    }

    // MARK: - Local git (through the shell)

    /// Local git is not available on iOS. What the shell's `git` command can do
    /// is report a checkout's state from a downloaded archive; anything that
    /// writes goes through the REST API above.
    func runGit(_ args: [String]) async -> WorkspaceShell.Output {
        guard let first = args.first?.lowercased() else {
            return WorkspaceShell.Output(
                status: 0,
                stdout: "usage: git [status|log|show|diff] — this build has no git binary; writes use the GitHub API",
                stderr: "",
                durationMs: 0
            )
        }
        switch first {
        case "status", "log", "show", "diff", "branch", "remote":
            let repo = linkedRepository?.fullName ?? "no linked repository"
            return WorkspaceShell.Output(
                status: 0,
                stdout: """
                linked repository: \(repo)
                git \(first): there is no git binary on iOS. Use "GitHub" in the Files tab to
                read a tree, read a file, commit a file, or dispatch a workflow.
                """,
                stderr: "",
                durationMs: 0
            )
        default:
            return WorkspaceShell.Output(
                status: 1,
                stdout: "",
                stderr: "git \(first) is not available on device. Writes go through the GitHub API.",
                durationMs: 0
            )
        }
    }
}
