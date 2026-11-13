import Foundation
import Combine
import UIKit

// MARK: - WorkspaceFileStore
//
// The app's own file shelf: everything the browser downloads, the user imports,
// or a GitHub action produces lands here, and everything here is readable by the
// assistant. Files live in Application Support so they survive reinstalls of the
// container but stay out of the Files-app mirror (the model files already own
// Documents; keeping two writers out of one folder avoids clobbering them).
//
// Deliberately small: a flat folder, no nesting, no versioning. The browsing and
// GitHub features need a place to put a file and a way to hand it to the model,
// which is exactly what this provides.

@MainActor
final class WorkspaceFileStore: ObservableObject {

    static let shared = WorkspaceFileStore()

    struct Entry: Identifiable, Hashable {
        let id: String          // file name; unique within the flat folder
        let url: URL
        let name: String
        let byteCount: Int64
        let modifiedAt: Date

        var isTextual: Bool { WorkspaceFileStore.isTextual(name) }
        var byteCountLabel: String { byteCount.formattedBytes }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var lastError: String?

    private let fileManager = FileManager.default

    // MARK: - Locations
    //
    // `directoryURL` is `nonisolated` on purpose: WKDownload's delegate asks for
    // a destination from a non-main thread and must answer synchronously.

    nonisolated static var directoryURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Workspace", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(
                at: base, withIntermediateDirectories: true
            )
        }
        return base
    }

    /// A name that does not collide with anything already on the shelf.
    nonisolated static func availableURL(for name: String) -> URL {
        let directory = directoryURL
        let safe = sanitized(name)
        var candidate = directory.appendingPathComponent(safe)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let base = (safe as NSString).deletingPathExtension
            let ext = (safe as NSString).pathExtension
            let next = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(next)
            counter += 1
        }
        return candidate
    }

    nonisolated static func sanitized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        if cleaned.isEmpty { return "download-\(Int(Date().timeIntervalSince1970))" }
        return String(cleaned.prefix(120))
    }

    private init() {
        createDirectoryIfNeeded()
        refresh()
    }

    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: Self.directoryURL.path) {
            try? fileManager.createDirectory(
                at: Self.directoryURL, withIntermediateDirectories: true
            )
        }
    }

    // MARK: - Reading

    func refresh() {
        createDirectoryIfNeeded()
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        let listing = (try? fileManager.contentsOfDirectory(
            at: Self.directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        entries = listing.compactMap { url -> Entry? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { return nil }
            return Entry(
                id: url.lastPathComponent,
                url: url,
                name: url.lastPathComponent,
                byteCount: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate ?? .distantPast
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Called after a WKDownload finishes. WKWebView writes the file itself, so
    /// there is nothing to move — only the listing to refresh, and the newest
    /// arrival to report.
    func refreshAfterDownload() async {
        refresh()
        if let newest = entries.first {
            ToastCenter.shared.success("Saved to Files", detail: newest.name)
        }
    }

    /// Text preview for the viewer and for the model. `nil` for binary types.
    func text(for entry: Entry, limit: Int = 400_000) -> String? {
        guard entry.isTextual else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: entry.url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: limit)) ?? Data()
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    /// Everything on the shelf, described for a prompt. Names, sizes, and the
    /// head of any text file, so the model can decide what to open.
    func catalogueBlock(maxTotalCharacters: Int = 12_000) -> String {
        guard !entries.isEmpty else { return "The Files shelf is empty." }
        var out = "Files on the shelf (\(entries.count)):\n"
        for entry in entries {
            out += "\n• \(entry.name) · \(entry.byteCountLabel) · \(entry.isTextual ? "text" : "binary")\n"
            guard out.count < maxTotalCharacters else { break }
        }
        return out
    }

    // MARK: - Writing

    @discardableResult
    func save(data: Data, name: String) throws -> Entry {
        createDirectoryIfNeeded()
        let url = Self.availableURL(for: name)
        try data.write(to: url, options: .atomic)
        refresh()
        return entries.first { $0.url.lastPathComponent == url.lastPathComponent }
            ?? Entry(id: url.lastPathComponent, url: url, name: url.lastPathComponent,
                     byteCount: Int64(data.count), modifiedAt: Date())
    }

    /// Copies a file the app was handed (a download temp file, a picker result)
    /// onto the shelf and returns the new entry.
    @discardableResult
    func adopt(fileAt source: URL, name: String? = nil) throws -> Entry {
        createDirectoryIfNeeded()
        let url = Self.availableURL(for: name ?? source.lastPathComponent)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.copyItem(at: source, to: url)
        refresh()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Entry(id: url.lastPathComponent, url: url, name: url.lastPathComponent,
                     byteCount: Int64(size), modifiedAt: Date())
    }

    func delete(_ entry: Entry) {
        do {
            try fileManager.removeItem(at: entry.url)
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func deleteAll() {
        for entry in entries { try? fileManager.removeItem(at: entry.url) }
        refresh()
    }

    // MARK: - Classification

    nonisolated static func isTextual(_ name: String) -> Bool {
        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "swift", "js", "mjs", "ts", "tsx",
            "jsx", "py", "rb", "sh", "bash", "zsh", "yml", "yaml", "toml", "ini",
            "cfg", "conf", "xml", "html", "htm", "css", "scss", "c", "h", "cpp",
            "hpp", "m", "mm", "rs", "go", "java", "kt", "kts", "lua", "sql",
            "csv", "tsv", "log", "plist", "entitlements", "patch", "diff", "svg"
        ]
        let ext = (name as NSString).pathExtension.lowercased()
        return textExtensions.contains(ext)
    }

    var totalByteCount: Int64 {
        entries.reduce(0) { $0 + $1.byteCount }
    }
}
