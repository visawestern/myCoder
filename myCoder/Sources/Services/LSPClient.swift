import Foundation
import Darwin

/// Tracks live language-server PIDs so app termination can stop them
/// synchronously. `Process` does not kill children when the app exits, and an
/// orphaned SourceKit-LSP would keep indexing in the background.
final class LSPProcessRegistry: @unchecked Sendable {
    static let shared = LSPProcessRegistry()
    private let lock = NSLock()
    private var pids: Set<pid_t> = []

    func register(_ pid: pid_t) {
        lock.lock()
        pids.insert(pid)
        lock.unlock()
    }

    func unregister(_ pid: pid_t) {
        lock.lock()
        pids.remove(pid)
        lock.unlock()
    }

    /// Send SIGTERM to every tracked server and forget them. Called from the
    /// app delegate's synchronous shutdown path.
    func terminateAll() {
        lock.lock()
        let snapshot = pids
        pids.removeAll()
        lock.unlock()
        for pid in snapshot {
            kill(pid, SIGTERM)
        }
    }
}

/// One live language-server process speaking LSP over stdio.
///
/// The client is an actor because the process reader runs on a background
/// queue while callers await responses from the main app: request IDs,
/// pending continuations, diagnostics and the read buffer all need one owner.
///
/// Lifecycle: `start()` launches the binary and performs `initialize` +
/// `initialized`; `shutdown()` asks the server to exit and terminates it.
/// Every request has a timeout so a wedged server can never hang a chat turn.
actor LSPClient {

    /// Everything needed to launch one server for one project root.
    struct Configuration: Sendable {
        let serverID: String
        let executable: String
        let arguments: [String]
        let projectRoot: String
        var requestTimeout: TimeInterval = 15
        var diagnosticsTimeout: TimeInterval = 30
    }

    /// Outcome of a diagnostics request: the report plus whether the server
    /// actually answered inside the timeout.
    struct DiagnosticsReport: Sendable {
        let serverID: String
        let path: String
        let diagnostics: [LSPDiagnostic]
        let timedOut: Bool
    }

    private struct OpenedDocument {
        var version: Int
        var text: String
        var languageID: String
    }

    private let configuration: Configuration
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stderrTail = Data()
    private var readBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Any, Error>] = [:]
    private var diagnosticsByURI: [String: [LSPDiagnostic]] = [:]
    private var freshURIs: Set<String> = []
    private var diagnosticWaiters: [String: [CheckedContinuation<DiagnosticsReport, Never>]] = [:]
    private var openedDocuments: [String: OpenedDocument] = [:]
    private var isInitialized = false
    private var isStopping = false

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    /// Launch the server and complete the LSP handshake.
    /// Input: none (configuration is captured at init). Output: none.
    /// Dependencies: Process, the server binary, `initialize` below.
    func start() async throws {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: configuration.executable) else {
            throw LSPClientError.executableNotFound(configuration.executable)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: configuration.executable)
        proc.arguments = configuration.arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: configuration.projectRoot)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.searchPath(environment["PATH"])
        proc.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.consume(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.rememberStderr(data) }
        }
        proc.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }

        do {
            try proc.run()
        } catch {
            throw LSPClientError.launchFailed(error.localizedDescription)
        }
        process = proc
        LSPProcessRegistry.shared.register(proc.processIdentifier)
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading

        do {
            try await initialize()
        } catch {
            await shutdown()
            throw error
        }
    }

    /// `initialize` + `initialized`. Kept separate so a failed handshake
    /// always tears the process down through the same path.
    private func initialize() async throws {
        let rootURI = LSPDocumentURI.make(path: configuration.projectRoot)
        let params: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "clientInfo": ["name": "myCoder", "version": "1.0"],
            "rootUri": rootURI,
            "rootPath": configuration.projectRoot,
            "workspaceFolders": [
                ["uri": rootURI,
                 "name": (configuration.projectRoot as NSString).lastPathComponent]
            ],
            "capabilities": [
                "workspace": [
                    "workspaceFolders": true,
                    "configuration": true
                ],
                "textDocument": [
                    "synchronization": ["didSave": true, "dynamicRegistration": false],
                    "publishDiagnostics": ["relatedInformation": true],
                    "hover": ["contentFormat": ["markdown", "plaintext"]],
                    "definition": ["linkSupport": true],
                    "references": ["dynamicRegistration": false],
                    "completion": [
                        "completionItem": [
                            "snippetSupport": false,
                            "documentationFormat": ["markdown", "plaintext"]
                        ]
                    ]
                ]
            ]
        ]
        _ = try await request(method: "initialize", params: params, timeout: 30)
        notify(method: "initialized", params: [:])
        isInitialized = true
    }

    /// Ask the server to exit, then terminate it. Idempotent.
    func shutdown() async {
        guard !isStopping else { return }
        isStopping = true
        if isInitialized {
            _ = try? await request(method: "shutdown", params: [:], timeout: 5)
            notify(method: "exit", params: [:])
        }
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        try? stdinHandle?.close()
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        if let proc = process {
            LSPProcessRegistry.shared.unregister(proc.processIdentifier)
        }
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        isInitialized = false
        failAllPending(with: LSPClientError.notRunning)
    }

    // MARK: - Documents

    /// Open the file, or send a full-text `didChange` when its bytes differ
    /// from what the server last saw. Input: absolute path. Output: none.
    /// Dependencies: LSPLanguageMap, the filesystem, the live server.
    func openDocument(path: String) throws {
        let uri = LSPDocumentURI.make(path: path)
        guard let language = LSPLanguageMap.language(forPath: path) else {
            throw LSPClientError.unsupportedLanguage(path)
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw LSPClientError.documentReadFailed(path)
        }
        if var existing = openedDocuments[uri] {
            guard existing.text != text else { return }
            existing.version += 1
            existing.text = text
            openedDocuments[uri] = existing
            freshURIs.remove(uri)
            notify(method: "textDocument/didChange", params: [
                "textDocument": ["uri": uri, "version": existing.version],
                "contentChanges": [["text": text]]
            ])
            return
        }
        openedDocuments[uri] = OpenedDocument(version: 1, text: text, languageID: language.id)
        freshURIs.remove(uri)
        notify(method: "textDocument/didOpen", params: [
            "textDocument": [
                "uri": uri,
                "languageId": language.id,
                "version": 1,
                "text": text
            ]
        ])
    }

    // MARK: - Diagnostics

    /// Wait for the server's next `publishDiagnostics` for this file.
    /// Input: absolute path + timeout. Output: report with `timedOut` set when
    /// no publish arrived. Dependencies: `openDocument`, notifications.
    func diagnostics(forPath path: String, timeout: TimeInterval? = nil) async -> DiagnosticsReport {
        let uri = LSPDocumentURI.make(path: path)
        do {
            try openDocument(path: path)
        } catch {
            return DiagnosticsReport(serverID: configuration.serverID, path: path,
                                     diagnostics: [], timedOut: true)
        }
        if freshURIs.contains(uri) {
            return DiagnosticsReport(serverID: configuration.serverID, path: path,
                                     diagnostics: diagnosticsByURI[uri] ?? [], timedOut: false)
        }
        let limit = timeout ?? configuration.diagnosticsTimeout
        return await withCheckedContinuation { continuation in
            diagnosticWaiters[uri, default: []].append(continuation)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, limit) * 1_000_000_000))
                await self?.expireDiagnostics(uri: uri, path: path)
            }
        }
    }

    // MARK: - Navigation requests

    func definition(path: String, line: Int, column: Int) async throws -> String {
        try openDocument(path: path)
        let result = try await request(
            method: "textDocument/definition",
            params: textDocumentPosition(path: path, line: line, column: column),
            timeout: configuration.requestTimeout
        )
        return LSPResultFormatting.locations(result, kind: "definition")
    }

    func references(path: String, line: Int, column: Int) async throws -> String {
        try openDocument(path: path)
        var params = textDocumentPosition(path: path, line: line, column: column)
        params["context"] = ["includeDeclaration": true]
        let result = try await request(
            method: "textDocument/references",
            params: params,
            timeout: configuration.requestTimeout
        )
        return LSPResultFormatting.locations(result, kind: "reference")
    }

    func hover(path: String, line: Int, column: Int) async throws -> String {
        try openDocument(path: path)
        let result = try await request(
            method: "textDocument/hover",
            params: textDocumentPosition(path: path, line: line, column: column),
            timeout: configuration.requestTimeout
        )
        return LSPResultFormatting.hover(result)
    }

    func completion(path: String, line: Int, column: Int, limit: Int = 30) async throws -> String {
        try openDocument(path: path)
        let result = try await request(
            method: "textDocument/completion",
            params: textDocumentPosition(path: path, line: line, column: column),
            timeout: configuration.requestTimeout
        )
        return LSPResultFormatting.completions(result, maxItems: limit)
    }

    /// Build the `TextDocumentPositionParams` object for a 1-based position.
    private func textDocumentPosition(path: String, line: Int, column: Int) -> [String: Any] {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let position = LSPPositionLogic.position(line: line, column: column, in: text)
        return [
            "textDocument": ["uri": LSPDocumentURI.make(path: path)],
            "position": ["line": position.line, "character": position.character]
        ]
    }

    // MARK: - Transport

    private func notify(method: String, params: Any) {
        guard let stdin = stdinHandle else { return }
        let payload: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? stdin.write(contentsOf: LSPMessageCodec.frame(json: data))
    }

    private func request(method: String, params: Any, timeout: TimeInterval) async throws -> Any {
        guard let stdin = stdinHandle else { throw LSPClientError.notRunning }
        let id = nextRequestID
        nextRequestID += 1
        let payload: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        ]
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw LSPClientError.encodingFailed(method)
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try stdin.write(contentsOf: LSPMessageCodec.frame(json: data))
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: LSPClientError.writeFailed)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000))
                await self?.expireRequest(id: id, method: method)
            }
        }
    }

    private func expireRequest(id: Int, method: String) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: LSPClientError.timeout(method))
    }

    private func consume(_ data: Data) {
        readBuffer.append(data)
        let decoded = LSPMessageCodec.decode(buffer: readBuffer)
        readBuffer = decoded.remaining
        for message in decoded.messages {
            handle(message)
        }
    }

    private func handle(_ message: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any] else {
            return
        }
        if let method = object["method"] as? String {
            if let id = object["id"] {
                respondToServerRequest(id: id, method: method)
            } else {
                handleNotification(method: method, params: object["params"] as? [String: Any] ?? [:])
            }
            return
        }
        guard let id = object["id"] as? Int,
              let continuation = pending.removeValue(forKey: id) else { return }
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown server error"
            continuation.resume(throwing: LSPClientError.serverError(message))
        } else {
            continuation.resume(returning: object["result"] ?? NSNull())
        }
    }

    /// Servers send requests during the session (`window/workDoneProgress/
    /// create`, `workspace/configuration`, `client/registerCapability`).
    /// Leaving them unanswered stalls the server, so every one gets a valid
    /// reply: an empty array for configuration, null for everything else.
    private func respondToServerRequest(id: Any, method: String) {
        let result: Any = method == "workspace/configuration" ? [] : NSNull()
        notifyRaw(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func notifyRaw(_ payload: [String: Any]) {
        guard let stdin = stdinHandle,
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? stdin.write(contentsOf: LSPMessageCodec.frame(json: data))
    }

    private func handleNotification(method: String, params: [String: Any]) {
        guard method == "textDocument/publishDiagnostics",
              let uri = params["uri"] as? String else { return }
        let diagnostics = decodeDiagnostics(params["diagnostics"])
        diagnosticsByURI[uri] = diagnostics
        freshURIs.insert(uri)
        let waiters = diagnosticWaiters.removeValue(forKey: uri) ?? []
        let report = DiagnosticsReport(serverID: configuration.serverID, path: uri,
                                       diagnostics: diagnostics, timedOut: false)
        for waiter in waiters {
            waiter.resume(returning: report)
        }
    }

    private func decodeDiagnostics(_ value: Any?) -> [LSPDiagnostic] {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return [] }
        return (try? JSONDecoder().decode([LSPDiagnostic].self, from: data)) ?? []
    }

    private func expireDiagnostics(uri: String, path: String) {
        guard let waiters = diagnosticWaiters.removeValue(forKey: uri) else { return }
        let report = DiagnosticsReport(serverID: configuration.serverID, path: path,
                                       diagnostics: diagnosticsByURI[uri] ?? [], timedOut: true)
        for waiter in waiters {
            waiter.resume(returning: report)
        }
    }

    private func rememberStderr(_ data: Data) {
        stderrTail.append(data)
        if stderrTail.count > 4096 {
            stderrTail = stderrTail.suffix(4096)
        }
    }

    private func handleTermination() {
        guard !isStopping else { return }
        let tail = String(decoding: stderrTail.suffix(600), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = tail.isEmpty ? "language server exited" : tail
        failAllPending(with: LSPClientError.serverError(detail))
        isInitialized = false
        if let proc = process {
            LSPProcessRegistry.shared.unregister(proc.processIdentifier)
        }
        process = nil
    }

    private func failAllPending(with error: LSPClientError) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
        for (uri, waiters) in diagnosticWaiters {
            let report = DiagnosticsReport(serverID: configuration.serverID, path: uri,
                                           diagnostics: diagnosticsByURI[uri] ?? [],
                                           timedOut: true)
            for waiter in waiters { waiter.resume(returning: report) }
        }
        diagnosticWaiters.removeAll()
    }

    /// PATH fallback so `xcrun`/wrappers can find sibling tools even when the
    /// app was launched from Finder with a minimal environment.
    private static func searchPath(_ existing: String?) -> String {
        let defaults = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
        guard let existing, !existing.isEmpty else { return defaults }
        return existing + ":" + defaults
    }
}

// MARK: - Errors

enum LSPClientError: LocalizedError, Equatable {
    case executableNotFound(String)
    case launchFailed(String)
    case notRunning
    case encodingFailed(String)
    case writeFailed
    case timeout(String)
    case serverError(String)
    case unsupportedLanguage(String)
    case documentReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path): return "language server executable not found: \(path)"
        case .launchFailed(let reason): return "language server failed to launch: \(reason)"
        case .notRunning: return "language server is not running"
        case .encodingFailed(let method): return "could not encode \(method) params"
        case .writeFailed: return "could not write to the language server"
        case .timeout(let method): return "language server timed out on \(method)"
        case .serverError(let message): return "language server error: \(message)"
        case .unsupportedLanguage(let path): return "no LSP language for \(path)"
        case .documentReadFailed(let path): return "cannot read \(path)"
        }
    }
}
