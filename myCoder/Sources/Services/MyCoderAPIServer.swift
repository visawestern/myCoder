import Foundation
import Network
import os.log

private let apiLog = OSLog(subsystem: "com.mycoder.app", category: "api")

/// Local HTTP API server for myCoder testing and integration.
/// Provides endpoints to list providers/models/chats and send messages.
final class MyCoderAPIServer {
    static let shared = MyCoderAPIServer()
    static let fixedPort: UInt16 = 8766
    /// Deadline for `POST /api/context-preview`. The preview runs the real
    /// pipeline: planner + impact + board build on a 1000-file project. The
    /// collection itself is capped by the shared five-minute budget
    /// (`ContextCollectionBudget.total`); this HTTP deadline only adds the
    /// room to hand the answer back, so the endpoint never becomes a second,
    /// larger ceiling for the collection itself (user directive 2026-11-08).
    static let contextPreviewDeadline: TimeInterval = ContextCollectionBudget.total + 60
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "mycoder.api.server")
    private(set) var port: Int = 0
    
    static func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            let url = MyCoderPaths.logFile(name: "api-server.log", homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Выполняет чтение на главном акторе и возвращает значение.
    ///
    /// Явная обёртка вместо `MainActor.run`: в Swift 6.3 его вывод типа
    /// требует `resultType:` при замыкании из одного выражения, а нам нужен
    /// простой читаемый вызов. Всё, что трогает `AppState`, обязано идти
    /// через этот помощник.
    @MainActor
    static func mainRead<T>(_ body: @MainActor () -> T) -> T {
        body()
    }
    
    /// Останавливает listener. Вызывается при выходе из приложения, чтобы
    /// последний запрос не ушёл в мост, который сейчас умрёт (живой прогон
    /// 2026-11-04). Повторный вызов — no-op.
    func stop() {
        listener?.cancel()
        listener = nil
        Self.appendLog("MyCoderAPIServer.stop() called")
    }

    func start() {
        Self.appendLog("MyCoderAPIServer.start() called")
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let port = NWEndpoint.Port(rawValue: Self.fixedPort)!
            // This API can mutate app state, so never expose it on the LAN.
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            listener = try NWListener(using: params)
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.port = Int(Self.fixedPort)
                    let msg = "myCoder API server ready on http://127.0.0.1:\(Self.fixedPort)"
                    os_log("%{public}@", log: apiLog, type: .info, msg)
                    Self.appendLog(msg)
                case .failed(let error):
                    Self.appendLog("API server failed: \(error)")
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: queue)
        } catch {
            print("Failed to start API server: \(error)")
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection)
    }
    
    private func receiveHTTPRequest(_ connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let data, !data.isEmpty {
                buffer.append(data)
            }
            guard !buffer.isEmpty else {
                connection.cancel()
                return
            }
            guard buffer.count <= 4 * 1024 * 1024 else {
                self.sendResponse(self.payloadTooLarge(), on: connection)
                return
            }

            let separator = Data("\r\n\r\n".utf8)
            guard let headerRange = buffer.range(of: separator) else {
                if isComplete {
                    connection.cancel()
                } else {
                    self.receiveHTTPRequest(connection, accumulated: buffer)
                }
                return
            }

            let header = String(decoding: buffer.prefix(upTo: headerRange.lowerBound), as: UTF8.self)
            let contentLength = Self.contentLength(in: header)
            let bodyStart = headerRange.upperBound
            let available = buffer.count - bodyStart
            guard available >= contentLength else {
                if isComplete {
                    connection.cancel()
                } else {
                    self.receiveHTTPRequest(connection, accumulated: buffer)
                }
                return
            }

            let body = String(decoding: buffer[bodyStart..<(bodyStart + contentLength)], as: UTF8.self)
            let lines = header.components(separatedBy: "\r\n")
            let requestLine = lines.first ?? ""
            let parts = requestLine.components(separatedBy: " ")
            let method = parts.count > 0 ? parts[0] : "GET"
            let rawPath = parts.count > 1 ? parts[1] : "/"
            var path = rawPath
            var query: String = ""
            if let queryStart = rawPath.firstIndex(of: "?") {
                path = String(rawPath[..<queryStart])
                query = String(rawPath[rawPath.index(after: queryStart)...])
            }
            // Аудит B1: каждый запрос обслуживается собственной задачей.
            // Долгий POST больше не держит очередь слушателя, а два чата
            // могут идти одновременно: у каждого свой `Task` и свой
            // `NWConnection`, общего семафора между ними нет.
            let priority: TaskPriority = Self.isHeavyRoute(method: method, path: path)
                ? .userInitiated
                : .utility
            Task(priority: priority) { [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                let response = await self.routeRequest(
                    method: method,
                    path: path,
                    body: body,
                    query: query
                )
                self.sendResponse(response, on: connection)
            }
        }
    }

    /// Классифицирует запрос: тяжёлые (долгие/мутирующие) получают более
    /// высокий приоритет задачи, чтобы долгий POST не ждал за быстрыми
    /// чтениями. Само выполнение всегда идёт в отдельной задаче.
    ///
    /// Вход: HTTP-метод и путь. Выход: true для POST и долгих GET
    /// (inspect/scroll/screenshot). Зависимости: нет.
    static func isHeavyRoute(method: String, path: String) -> Bool {
        if method == "POST" { return true }
        let heavyReads = ["/api/inspect", "/api/scroll", "/api/screenshot"]
        return heavyReads.contains(path)
    }

    private static func contentLength(in header: String) -> Int {
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else {
                continue
            }
            return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    private func sendResponse(_ response: String, on connection: NWConnection) {
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func payloadTooLarge() -> String {
        return "HTTP/1.1 413 Payload Too Large\r\nContent-Type: application/json\r\n\r\n{\"error\":\"request body exceeds 4 MB\"}"
    }

    private func routeRequest(method: String, path: String, body: String, query: String = "") async -> String {
        switch (method, path) {
        case ("GET", "/api/actions"):
            return await handleActions()
        case ("POST", "/api/action"):
            return await handleAction(body: body)
        case ("GET", "/api/state"):
            return await handleState()
        case ("GET", "/api/providers"):
            return await jsonResponse(providersInfo())
        case ("GET", "/api/chats"):
            return await jsonResponse(chatsInfo())
        case ("GET", "/api/messages"):
            return await jsonResponse(messagesInfo())
        case ("POST", "/api/send"):
            return await handleSend(body: body)
        case ("POST", "/api/select"):
            return await handleSelect(body: body)
        case ("POST", "/api/refresh-models"):
            return await handleRefreshModels(body: body)
        case ("POST", "/api/evaluate"):
            return await handleEvaluate(body: body)
        case ("GET", "/api/webviews"):
            return await handleWebviews()
        case ("POST", "/api/save-session"):
            return await handleSaveSession(body: body)
        case ("GET", "/api/inspect"):
            return await handleInspect(body: body)
        case ("POST", "/api/inspect"):
            return await handleInspect(body: body)
        case ("GET", "/api/debug/cursor"):
            return await handleCursorDebug()
        case ("POST", "/api/discover-models"):
            return await handleDiscoverModels()
        case ("POST", "/api/add-account"):
            return await handleAddAccount(body: body)
        case ("POST", "/api/add-vendor"):
            return await handleAddVendor(body: body)
        case ("POST", "/api/web-login-check"):
            return await handleWebLoginCheck(body: body)
        case ("GET", "/api/web-login-status"):
            return await handleWebLoginStatus()
        case ("POST", "/api/open-login"):
            return await handleOpenLogin(body: body)
        case ("POST", "/api/send-and-wait"):
            return await handleSendAndWait(body: body)
        case ("POST", "/api/update-provider-url"):
            return await handleUpdateProviderURL(body: body)
        case ("POST", "/api/set-web-model"):
            return await handleSetWebModel(body: body)
        case ("GET", "/api/scroll"):
            return await handleScroll(query: query)
        case ("POST", "/api/scroll"):
            return await handleScroll(body: body, query: query)
        case ("GET", "/api/screenshot"):
            return await handleScreenshot(query: query)
        case ("GET", "/api/markdown-perf"):
            return jsonResponse(MarkdownAttributedStringBuilder.statsSnapshot().dictionary)
        case ("POST", "/api/markdown-perf/reset"):
            MarkdownAttributedStringBuilder.resetStats()
            return jsonResponse(["ok": true])
        case ("POST", "/api/context-preview"):
            return await handleContextPreview(body: body)
        default:
            return notFound()
        }
    }
    




}
