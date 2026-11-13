import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - LASFilesView
//
// The Files tab: the shelf the browser and the GitHub tools write into, with a
// viewer, a shell, and the GitHub panel. Laid out like the rest of the app so it
// reads as one product rather than a bolted-on file manager.

struct LASFilesView: View {

    @ObservedObject private var store = WorkspaceFileStore.shared
    @ObservedObject private var shell = WorkspaceShell.shared
    @ObservedObject private var git = GitService.shared
    @Environment(\.koduTheme) private var T

    @State private var selected: WorkspaceFileStore.Entry?
    @State private var showingImporter = false
    @State private var showingGitHub = false
    @State private var shellInput = ""
    @State private var showingShell = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(T.rule)

            ScrollView {
                VStack(alignment: .leading, spacing: LASDesignTokens.component) {
                    if store.entries.isEmpty {
                        emptyState
                    } else {
                        fileList
                    }
                    if showingShell { shellCard }
                    if !git.repositories.isEmpty { gitCard }
                }
                .padding(.horizontal, LASDesignTokens.pageInset)
                .padding(.top, LASDesignTokens.row)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .refreshable { store.refresh() }
        }
        .background(LASPageBackground())
        .sheet(item: $selected) { entry in
            LASFileDetailView(entry: entry).lasTheme()
        }
        .sheet(isPresented: $showingGitHub) {
            LASGitHubView().lasTheme()
        }
        .sheet(isPresented: $showingImporter) {
            LASDocumentPicker { url in
                showingImporter = false
                importFile(at: url)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: LASDesignTokens.tight) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Files")
                    .font(.headline.weight(.semibold))
                Text("\(store.entries.count) items · \(store.totalByteCount.formattedBytes)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            iconButton("plus", label: "Import a file") { showingImporter = true }
            iconButton("chevron.left.forwardslash.chevron.right", label: "Shell") {
                withAnimation(.easeInOut(duration: 0.2)) { showingShell.toggle() }
            }
            iconButton("cat.fill", label: "GitHub") { showingGitHub = true }
        }
        .padding(.horizontal, LASDesignTokens.pageInset)
        .padding(.vertical, LASDesignTokens.tight)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Color.primary.opacity(0.055), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
    }

    // MARK: - List

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(store.entries) { entry in
                Button {
                    selected = entry
                } label: {
                    HStack(spacing: LASDesignTokens.row) {
                        Image(systemName: icon(for: entry))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(entry.isTextual ? T.accentStrong : .secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(entry.byteCountLabel) · \(entry.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(T.ink4)
                    }
                    .padding(.horizontal, LASDesignTokens.component)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if entry.id != store.entries.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .lasCard(radius: LASDesignTokens.cardRadius, padding: 0)
    }

    private func icon(for entry: WorkspaceFileStore.Entry) -> String {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":                 return "swift"
        case "sh", "bash", "zsh":     return "terminal"
        case "md", "markdown", "txt": return "doc.text"
        case "json", "yml", "yaml", "plist": return "curlybraces"
        case "png", "jpg", "jpeg", "heic", "gif": return "photo"
        case "pdf":                   return "doc.richtext"
        case "zip", "gz", "tar", "ipa": return "shippingbox"
        default:                      return entry.isTextual ? "doc.plaintext" : "doc"
        }
    }

    private var emptyState: some View {
        VStack(spacing: LASDesignTokens.tight) {
            Image(systemName: "folder")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing here yet")
                .font(.subheadline.weight(.semibold))
            Text("Downloads from the browser, files the assistant writes, and imports land on this shelf. Everything here is readable by the model.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LASDesignTokens.section)
        .lasCard()
    }

    // MARK: - Shell

    private var shellCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
            LASSectionLabel(title: "SHELL", trailing: shell.isRunning ? "RUNNING" : "IDLE")

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if shell.transcript.isEmpty {
                        Text("ls · cat <file> · grep <pattern> · head <file> · wc <file> · swift <file> · git status")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(shell.transcript.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 180)

            HStack(spacing: 6) {
                TextField("command", text: $shellInput)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { runShell() }
                Button {
                    runShell()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(T.accentStrong)
                }
                .buttonStyle(.plain)
                .disabled(shellInput.isEmpty || shell.isRunning)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            Text("No compiler, package manager, or virtual machine on device: iOS forbids fork/exec and JIT. Compilation runs in Actions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lasCard()
    }

    private func runShell() {
        let command = shellInput
        guard !command.isEmpty else { return }
        shellInput = ""
        Task { await shell.run(command) }
    }

    // MARK: - GitHub summary

    private var gitCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
            LASSectionLabel(
                title: "GITHUB",
                trailing: (git.linkedRepository?.fullName ?? "NOT LINKED").uppercased()
            )
            Text(git.linkedRepository?.fullName ?? "No repository linked yet.")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Button("Open GitHub") { showingGitHub = true }
                .buttonStyle(LASSecondaryButtonStyle())
        }
        .lasCard()
    }

    // MARK: - Import

    private func importFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try WorkspaceFileStore.shared.adopt(fileAt: url)
        } catch {
            ToastCenter.shared.error("Import failed", detail: error.localizedDescription)
        }
    }
}

// MARK: - File detail

struct LASFileDetailView: View {

    let entry: WorkspaceFileStore.Entry
    @ObservedObject private var store = WorkspaceFileStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.koduTheme) private var T

    var body: some View {
        VStack(spacing: 0) {
            LASDetailHeader(entry.name) {
                Button {
                    store.delete(entry)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(LASHeaderIconButtonStyle(dark: false))
                .accessibilityLabel("Delete file")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: LASDesignTokens.component) {
                    HStack(spacing: LASDesignTokens.row) {
                        LASMetricTile(
                            title: "size",
                            value: entry.byteCountLabel,
                            detail: entry.isTextual ? "text" : "binary",
                            symbol: entry.isTextual ? "doc.plaintext" : "doc"
                        )
                    }

                    if let text = store.text(for: entry) {
                        Text(text)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("This file is not text, so there is nothing to preview. The model can still see that it exists and how large it is.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, LASDesignTokens.pageInset)
                .padding(.bottom, 28)
            }
        }
        .background(LASPageBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Document picker

struct LASDocumentPicker: UIViewControllerRepresentable {

    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.plainText, .sourceCode, .json, .data, .item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
