import Foundation
import Combine

// MARK: - WorkspaceShell
//
// A tiny in-app shell. iOS has no fork/exec for arbitrary binaries, so this is
// not a general-purpose shell: it runs a fixed, audited command set against the
// Files shelf. That is enough for what the agent needs it for — look at a file,
// search it, compile the Swift or shell the shelf holds, and run git.
//
// Every command is parsed into a struct first, so a call is either in the set or
// rejected; nothing is ever passed to a system() call.

@MainActor
final class WorkspaceShell: ObservableObject {

    static let shared = WorkspaceShell()

    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        let durationMs: Int

        var combined: String {
            var text = stdout
            if !stderr.isEmpty {
                if !text.isEmpty { text += "\n" }
                text += stderr
            }
            return text.isEmpty ? "(no output)" : text
        }
    }

    @Published private(set) var transcript: [String] = []
    @Published private(set) var isRunning = false

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Command set

    enum Command {
        /// `ls` — the shelf.
        case list
        /// `cat <name>` — a text file's contents.
        case read(String)
        /// `grep <pattern> [name…]` — literal substring search.
        case grep(String, [String])
        /// `wc <name>` — lines, words, bytes.
        case wordCount(String)
        /// `head <name> [n]`
        case head(String, Int)
        /// `swift <name>.swift` — compile and run with the interpreter.
        case swift(String)
        /// `sh <name>.sh` — run a shell script from the shelf.
        case shell(String)
        /// `git <args…>` — restricted to the configured repository folder.
        case git([String])
        /// `pwd` / `echo <text>` / `date` — context helpers.
        case echo(String)
        case date
        /// Anything else.
        case unsupported(String)
    }

    nonisolated static func parse(_ line: String) -> Command {
        let tokens = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard let head = tokens.first?.lowercased() else { return .echo("") }
        let rest = Array(tokens.dropFirst())
        switch head {
        case "ls", "dir":        return .list
        case "pwd":              return .echo("/workspace (the Files shelf)")
        case "date":             return .date
        case "cat":
            guard let name = rest.first else { return .unsupported("cat needs a file name") }
            return .read(name)
        case "wc":
            guard let name = rest.first else { return .unsupported("wc needs a file name") }
            return .wordCount(name)
        case "head":
            guard let name = rest.first else { return .unsupported("head needs a file name") }
            let count = rest.count > 1 ? (Int(rest[1]) ?? 40) : 40
            return .head(name, max(1, min(count, 2_000)))
        case "grep":
            guard let pattern = rest.first else {
                return .unsupported("grep needs a pattern")
            }
            return .grep(pattern, Array(rest.dropFirst()))
        case "swift":
            guard let name = rest.first else { return .unsupported("swift needs a file name") }
            return .swift(name)
        case "sh", "bash":
            guard let name = rest.first else { return .unsupported("sh needs a file name") }
            return .shell(name)
        case "git":
            return .git(rest)
        case "echo":
            return .echo(rest.joined(separator: " "))
        default:
            return .unsupported("'\(head)' is not available in this shell")
        }
    }

    // MARK: - Execution

    @discardableResult
    func run(_ line: String) async -> Output {
        isRunning = true
        defer { isRunning = false }
        transcript.append("$ \(line)")

        let started = Date()
        let output: Output
        switch Self.parse(line) {
        case .echo(let text):
            output = Output(status: 0, stdout: text, stderr: "", durationMs: 0)
        case .date:
            let formatter = ISO8601DateFormatter()
            output = Output(status: 0, stdout: formatter.string(from: Date()), stderr: "", durationMs: 0)
        case .list:
            let names = WorkspaceFileStore.shared.entries
                .map { "\($0.name)\t\($0.byteCountLabel)" }
                .joined(separator: "\n")
            output = Output(status: 0, stdout: names, stderr: "", durationMs: 0)
        case .read(let name):
            output = Self.readText(named: name)
        case .wordCount(let name):
            output = Self.wordCount(named: name)
        case .head(let name, let count):
            output = Self.head(named: name, count: count)
        case .grep(let pattern, let files):
            output = Self.grep(pattern: pattern, files: files)
        case .swift(let name):
            output = await Self.runSwift(named: name)
        case .shell(let name):
            output = await Self.runScript(named: name)
        case .git(let args):
            output = await GitService.shared.runGit(args)
        case .unsupported(let reason):
            output = Output(status: 127, stdout: "", stderr: reason, durationMs: 0)
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        let finished = Output(
            status: output.status,
            stdout: output.stdout,
            stderr: output.stderr,
            durationMs: elapsed
        )
        transcript.append(finished.combined)
        if transcript.count > 200 {
            transcript.removeFirst(transcript.count - 200)
        }
        return finished
    }

    func clearTranscript() {
        transcript.removeAll()
    }

    // MARK: - Locating files

    nonisolated static func locate(_ name: String) -> URL? {
        let directory = WorkspaceFileStore.directoryURL
        let direct = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        // Fall back to a suffix match so "main.swift" finds "repo-main.swift".
        let listing = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return listing.first { $0.lastPathComponent.hasSuffix(name) }
    }

    // MARK: - Built-ins

    nonisolated private static func readText(named name: String) -> Output {
        guard let url = locate(name) else {
            return Output(status: 1, stdout: "", stderr: "no such file: \(name)", durationMs: 0)
        }
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else {
            return Output(status: 1, stdout: "", stderr: "could not read \(name)", durationMs: 0)
        }
        guard let text = String(data: data.prefix(400_000), encoding: .utf8) else {
            return Output(status: 1, stdout: "", stderr: "\(name) is not UTF-8 text", durationMs: 0)
        }
        return Output(status: 0, stdout: text, stderr: "", durationMs: 0)
    }

    nonisolated private static func wordCount(named name: String) -> Output {
        guard let url = locate(name),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return Output(status: 1, stdout: "", stderr: "no such text file: \(name)", durationMs: 0)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let bytes = text.utf8.count
        return Output(status: 0, stdout: "\(lines)\t\(words)\t\(bytes)\t\(name)",
                      stderr: "", durationMs: 0)
    }

    nonisolated private static func head(named name: String, count: Int) -> Output {
        guard let url = locate(name),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return Output(status: 1, stdout: "", stderr: "no such text file: \(name)", durationMs: 0)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return Output(status: 0, stdout: lines.prefix(count).joined(separator: "\n"),
                      stderr: "", durationMs: 0)
    }

    nonisolated private static func grep(pattern: String, files: [String]) -> Output {
        let targets: [URL]
        if files.isEmpty {
            let directory = WorkspaceFileStore.directoryURL
            targets = ((try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )) ?? []).filter { WorkspaceFileStore.isTextual($0.lastPathComponent) }
        } else {
            targets = files.compactMap { locate($0) }
        }
        var hits: [String] = []
        for url in targets {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if line.localizedCaseInsensitiveContains(pattern) {
                    hits.append("\(url.lastPathComponent):\(index + 1): \(line)")
                    if hits.count >= 200 { break }
                }
            }
            if hits.count >= 200 { break }
        }
        if hits.isEmpty {
            return Output(status: 1, stdout: "", stderr: "no matches for '\(pattern)'", durationMs: 0)
        }
        return Output(status: 0, stdout: hits.joined(separator: "\n"), stderr: "", durationMs: 0)
    }

    // MARK: - Compile / run
    //
    // iOS ships a Swift toolchain in the OS but no compiler the app may invoke,
    // and it never ships `cc`. So the honest answer is: swiftc is unavailable on
    // device; compilation happens in the source compiler's CI. What this does
    // instead is real and useful — it type-checks nothing but it does resolve the
    // file, surface syntax-visible problems it can see (unbalanced braces,
    // missing imports for common symbols), and hand the file to the Actions
    // workflow when the user wants a real build.

    nonisolated static func runSwift(named name: String) async -> Output {
        guard let url = locate(name) else {
            return Output(status: 1, stdout: "", stderr: "no such file: \(name)", durationMs: 0)
        }
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            return Output(status: 1, stdout: "", stderr: "could not read \(name)", durationMs: 0)
        }

        let lint = swiftLint(source: source, fileName: url.lastPathComponent)
        if lint.status != 0 { return lint }

        return Output(
            status: 0,
            stdout: """
            \(url.lastPathComponent): structural checks passed.
            This device has no Swift compiler, so nothing was executed. Use
            "Build on GitHub" to compile it in Actions and get an artifact, or
            run it on a Mac with Xcode.
            """,
            stderr: "",
            durationMs: 0
        )
    }

    /// Real, cheap checks: balanced delimiters, unterminated strings, and a note
    /// on symbols that need an import. Deliberately conservative — a false
    /// "error" is worse than saying nothing.
    nonisolated static func swiftLint(source: String, fileName: String) -> Output {
        var problems: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var lineNumber = 1

        for character in source {
            if character == "\n" { lineNumber += 1 }
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth < 0 {
                    problems.append("line \(lineNumber): extra closing brace")
                    depth = 0
                }
            default: break
            }
        }
        if inString {
            problems.append("a string literal is never closed")
        }
        if depth != 0 {
            problems.append("\(depth) unclosed opening brace(s)")
        }

        let imports = Set(source.split(separator: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }
            .map { $0.trimmingCharacters(in: .whitespaces) })
        if source.contains("URLSession") && !imports.contains("import Foundation") {
            problems.append("uses URLSession but does not import Foundation")
        }
        if source.contains("UIApplication") && !imports.contains("import UIKit") {
            problems.append("uses UIApplication but does not import UIKit")
        }

        if problems.isEmpty {
            return Output(status: 0, stdout: "", stderr: "", durationMs: 0)
        }
        return Output(
            status: 1,
            stdout: "",
            stderr: problems.map { "\(fileName): \($0)" }.joined(separator: "\n"),
            durationMs: 0
        )
    }

    nonisolated static func runScript(named name: String) async -> Output {
        guard let url = locate(name),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            return Output(status: 1, stdout: "", stderr: "no such script: \(name)", durationMs: 0)
        }
        // No /bin/sh on device for scripts. Report what the script would do so
        // the model can reason about it, and point at Actions for real runs.
        let lines = script.split(separator: "\n").prefix(60)
        return Output(
            status: 0,
            stdout: """
            \(url.lastPathComponent): \(lines.count) lines, not executed.
            iOS has no shell for script files. First lines:
            \(lines.joined(separator: "\n"))
            """,
            stderr: "",
            durationMs: 0
        )
    }
}
