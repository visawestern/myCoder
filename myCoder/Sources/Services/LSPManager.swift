import Foundation

/// Owns the live language-server processes for the app.
///
/// One client per server id is reused across turns: starting SourceKit-LSP
/// costs seconds, so edits in the same project must not spawn a new server
/// every time. A failed start is remembered so a broken binary does not cost
/// a launch attempt on every keystroke; `resetFailures()` lets the settings
/// screen retry after the user fixes the command.
actor LSPManager {

    static let shared = LSPManager()

    private let homeDirectory: URL
    private let fileManager: FileManager
    private var clients: [String: LSPClient] = [:]
    private var failures: [String: String] = [:]

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         fileManager: FileManager = .default) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    /// The enabled server for this file, started on first use.
    /// Input: file path + project root. Output: a ready client, or nil when
    /// no enabled server covers the language. Dependencies: the LSP registry,
    /// executable resolution, `LSPClient.start`.
    func client(forPath path: String, projectRoot: String) async -> LSPClient? {
        let records = LSPRegistryManager.load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let record = LSPServerSelection.select(records: records, path: path) else {
            return nil
        }
        if let client = clients[record.id] { return client }
        if failures[record.id] != nil { return nil }
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        guard let executable = LSPDiscovery.resolveExecutable(
            record.command, searchPath: searchPath, fileManager: fileManager
        ) else {
            failures[record.id] = "executable not found: \(record.command)"
            return nil
        }
        let client = LSPClient(configuration: .init(
            serverID: record.id,
            executable: executable,
            arguments: record.args,
            projectRoot: projectRoot
        ))
        do {
            try await client.start()
            clients[record.id] = client
            return client
        } catch {
            failures[record.id] = error.localizedDescription
            return nil
        }
    }

    /// Diagnostics for one file as a formatted report, or nil when no server
    /// is configured for its language. Input: path + project root.
    /// Output: text for the model (clean files still get a one-line report).
    func diagnosticsSummary(path: String, projectRoot: String,
                            timeout: TimeInterval? = nil) async -> String? {
        guard let client = await client(forPath: path, projectRoot: projectRoot) else {
            return nil
        }
        let report = await client.diagnostics(forPath: path, timeout: timeout)
        let body = LSPDiagnosticsFormatter.summary(
            path: displayPath(path, projectRoot: projectRoot),
            diagnostics: report.diagnostics
        )
        if report.timedOut {
            return body + "\n(note: the language server did not publish diagnostics in time)"
        }
        return body
    }

    /// Run one explicit LSP operation for the agent's `lsp` tool.
    /// Input: operation + file position. Output: formatted text; errors are
    /// returned as `error: …` so the tool call never throws into the turn.
    /// Dependencies: the selected client, `LSPResultFormatting`.
    func perform(operation: String,
                 path: String,
                 projectRoot: String,
                 line: Int,
                 column: Int,
                 limit: Int = 30) async -> String {
        guard let client = await client(forPath: path, projectRoot: projectRoot) else {
            return "error: no enabled language server covers \(path). Enable one in Settings → Language Servers (LSP)."
        }
        do {
            switch operation {
            case "diagnostics":
                let report = await client.diagnostics(forPath: path)
                let text = LSPDiagnosticsFormatter.summary(
                    path: displayPath(path, projectRoot: projectRoot),
                    diagnostics: report.diagnostics
                )
                return report.timedOut
                    ? text + "\n(note: the language server did not publish diagnostics in time)"
                    : text
            case "definition":
                return try await client.definition(path: path, line: line, column: column)
            case "references":
                return try await client.references(path: path, line: line, column: column)
            case "hover":
                return try await client.hover(path: path, line: line, column: column)
            case "completion":
                return try await client.completion(path: path, line: line, column: column, limit: limit)
            default:
                return "error: unknown LSP operation '\(operation)' (use diagnostics, definition, references, hover, completion)"
            }
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    /// Stop every live server (app termination, settings reset).
    func shutdownAll() async {
        let live = clients.values
        clients.removeAll()
        for client in live {
            await client.shutdown()
        }
    }

    /// Allow a failed server to be launched again after the user edits its
    /// configuration. Input: optional id (nil clears all). Output: none.
    func resetFailures(serverID: String? = nil) {
        if let serverID {
            failures.removeValue(forKey: serverID)
        } else {
            failures.removeAll()
        }
    }

    private func displayPath(_ path: String, projectRoot: String) -> String {
        let root = projectRoot.hasSuffix("/") ? projectRoot : projectRoot + "/"
        guard path.hasPrefix(root) else { return path }
        return String(path.dropFirst(root.count))
    }
}
