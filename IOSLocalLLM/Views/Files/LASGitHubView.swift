import SwiftUI

// MARK: - LASGitHubView
//
// Link a GitHub account with a personal access token, pick the repository the
// assistant works against, read its tree, dispatch the build workflow, and see
// the runs and releases that come back.
//
// The token is written straight to the Keychain and is never shown again; the
// field is not pre-filled, so a shoulder-surfer cannot re-read it.

struct LASGitHubView: View {

    @ObservedObject private var git = GitService.shared
    @ObservedObject private var files = WorkspaceFileStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.koduTheme) private var T

    @State private var tokenInput = ""
    @State private var filter = ""
    @State private var status: String?
    @State private var busy = false

    private var filtered: [GitService.Repository] {
        guard !filter.isEmpty else { return git.repositories }
        return git.repositories.filter {
            $0.fullName.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LASDesignTokens.component) {
                    accountCard
                    if git.hasToken {
                        linkedCard
                        repositoryCard
                        actionsCard
                        runsCard
                        releasesCard
                    }
                    privacyCard
                }
                .padding(.horizontal, LASDesignTokens.pageInset)
                .padding(.bottom, 32)
            }
            .background(LASPageBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay(alignment: .top) {
            LASDetailHeader("GitHub") {
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.row) {
            LASSectionLabel(
                title: "ACCOUNT",
                trailing: git.hasToken ? (git.accountLogin ?? "CONNECTED").uppercased() : "NOT LINKED"
            )

            if git.hasToken {
                HStack(spacing: LASDesignTokens.row) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(T.good)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Token saved in Keychain")
                            .font(.subheadline.weight(.semibold))
                        Text("repo scope · read and write")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Remove") { git.clearToken() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(T.bad)
                        .buttonStyle(.plain)
                }
            } else {
                Text("Paste a personal access token with repo scope. The assistant can then read your repositories, commit a file, and dispatch the build workflow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("ghp_…", text: $tokenInput)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                Button {
                    saveToken()
                } label: {
                    Text("Save token").frame(maxWidth: .infinity)
                }
                .buttonStyle(LASPrimaryButtonStyle())
                .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .lasCard()
    }

    private func saveToken() {
        git.saveToken(tokenInput)
        tokenInput = ""
        busy = true
        Task {
            await git.loadAccount()
            await git.loadRepositories()
            busy = false
            status = git.repositories.isEmpty
                ? "Token saved, but no repositories came back."
                : "\(git.repositories.count) repositories loaded."
        }
    }

    // MARK: - Linked

    private var linkedCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.row) {
            LASSectionLabel(title: "LINKED REPOSITORY")
            if let repository = git.linkedRepository {
                Text(repository.fullName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(repository.isPrivate ? "private" : "public") · \(repository.defaultBranch)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("Pick one below. The assistant reads and commits to this repository by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lasCard()
    }

    // MARK: - Repositories

    private var repositoryCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
            HStack {
                LASSectionLabel(title: "REPOSITORIES", trailing: "\(filtered.count)")
                Spacer(minLength: 0)
                Button {
                    busy = true
                    Task {
                        await git.loadRepositories()
                        busy = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            TextField("Filter", text: $filter)
                .font(.caption)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            if busy {
                ProgressView().frame(maxWidth: .infinity)
            }

            ForEach(filtered.prefix(40)) { repository in
                Button {
                    git.link(repository)
                    Task {
                        await git.loadRuns(repository: repository)
                        await git.loadReleases(repository: repository)
                    }
                } label: {
                    HStack(spacing: LASDesignTokens.tight) {
                        Image(systemName: repository.isPrivate ? "lock.fill" : "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(repository.fullName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        if git.linkedRepository?.id == repository.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(T.accentStrong)
                        }
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error = git.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(T.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lasCard()
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsCard: some View {
        if let repository = git.linkedRepository {
            VStack(alignment: .leading, spacing: LASDesignTokens.row) {
                LASSectionLabel(title: "ACTIONS")

                Button {
                    busy = true
                    Task {
                        let result = await git.dispatchWorkflow(repository: repository)
                        busy = false
                        switch result {
                        case .success(let message): status = message
                        case .failure(let failure): status = failure.message
                        }
                        await git.loadRuns(repository: repository)
                    }
                } label: {
                    Label("Run checks on GitHub", systemImage: "hammer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LASPrimaryButtonStyle())
                .disabled(busy)

                Button {
                    busy = true
                    Task {
                        await git.loadRuns(repository: repository)
                        await git.loadReleases(repository: repository)
                        busy = false
                        status = "Refreshed runs and releases."
                    }
                } label: {
                    Label("Refresh runs and releases", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LASSecondaryButtonStyle())
                .disabled(busy)

                Text("Starts the validate workflow: it parses every Swift file. The IPA is built by Codemagic from codemagic.yaml, which has to be started on codemagic.io. Dispatch needs the workflow on the default branch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .lasCard()
        }
    }

    // MARK: - Runs / releases

    @ViewBuilder
    private var runsCard: some View {
        if !git.runs.isEmpty {
            VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
                LASSectionLabel(title: "RUNS", trailing: "\(git.runs.count)")
                ForEach(git.runs.prefix(8)) { run in
                    HStack(spacing: LASDesignTokens.tight) {
                        Image(systemName: symbol(for: run))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color(for: run))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(run.name).font(.caption).lineLimit(1)
                            Text("\(run.branch) · \(run.conclusion ?? run.status)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let url = run.htmlURL {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .lasCard()
        }
    }

    private func symbol(for run: GitService.WorkflowRun) -> String {
        switch run.conclusion {
        case "success":          return "checkmark.circle.fill"
        case "failure":          return "xmark.circle.fill"
        case "cancelled":        return "slash.circle.fill"
        default:
            return run.status == "completed" ? "circle" : "clock"
        }
    }

    private func color(for run: GitService.WorkflowRun) -> Color {
        switch run.conclusion {
        case "success": return T.good
        case "failure": return T.bad
        default:        return T.ink3
        }
    }

    @ViewBuilder
    private var releasesCard: some View {
        if !git.releases.isEmpty {
            VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
                LASSectionLabel(title: "RELEASES", trailing: "\(git.releases.count)")
                ForEach(git.releases.prefix(5)) { release in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(release.name).font(.caption.weight(.semibold))
                            Spacer(minLength: 0)
                            if let url = release.htmlURL {
                                Link(destination: url) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                        }
                        if !release.assetNames.isEmpty {
                            Text(release.assetNames.joined(separator: " · "))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .lasCard()
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
            LASSectionLabel(title: "PRIVACY")
            Text("The token is stored in the iOS Keychain and sent only to api.github.com over HTTPS. Repository content you read is kept in memory for the turn unless you save it to Files.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lasCard()
    }
}
