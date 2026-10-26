import Foundation
import Network
import os.log

private let apiLog = OSLog(subsystem: "com.mycoder.app", category: "api")

/// Local HTTP API server for myCoder testing and integration.
/// Provides endpoints to list providers/models/chats and send messages.
final class MyCoderAPIServer {
    static let shared = MyCoderAPIServer()
    static let fixedPort: UInt16 = 8766
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
    
    func start() {
        Self.appendLog("MyCoderAPIServer.start() called")
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
            let path = parts.count > 1 ? parts[1] : "/"
            let response = self.routeRequest(method: method, path: path, body: body)
            self.sendResponse(response, on: connection)
        }
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

    private func routeRequest(method: String, path: String, body: String) -> String {
        switch (method, path) {
        case ("GET", "/api/actions"):
            return handleActions()
        case ("POST", "/api/action"):
            return handleAction(body: body)
        case ("GET", "/api/state"):
            return handleState()
        case ("GET", "/api/providers"):
            return jsonResponse(providersInfo())
        case ("GET", "/api/chats"):
            return jsonResponse(chatsInfo())
        case ("GET", "/api/messages"):
            return jsonResponse(messagesInfo())
        case ("POST", "/api/send"):
            return handleSend(body: body)
        case ("POST", "/api/select"):
            return handleSelect(body: body)
        case ("POST", "/api/refresh-models"):
            return handleRefreshModels(body: body)
        case ("POST", "/api/evaluate"):
            return handleEvaluate(body: body)
        case ("GET", "/api/webviews"):
            return handleWebviews()
        case ("POST", "/api/save-session"):
            return handleSaveSession(body: body)
        case ("GET", "/api/inspect"):
            return handleInspect(body: body)
        case ("POST", "/api/inspect"):
            return handleInspect(body: body)
        case ("POST", "/api/discover-models"):
            return handleDiscoverModels()
        case ("POST", "/api/add-account"):
            return handleAddAccount(body: body)
        case ("POST", "/api/add-vendor"):
            return handleAddVendor(body: body)
        case ("POST", "/api/web-login-check"):
            return handleWebLoginCheck(body: body)
        case ("GET", "/api/web-login-status"):
            return handleWebLoginStatus()
        case ("POST", "/api/open-login"):
            return handleOpenLogin(body: body)
        case ("POST", "/api/send-and-wait"):
            return handleSendAndWait(body: body)
        case ("POST", "/api/update-provider-url"):
            return handleUpdateProviderURL(body: body)
        case ("POST", "/api/set-web-model"):
            return handleSetWebModel(body: body)
        default:
            return notFound()
        }
    }
    
    private func handleActions() -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var actions: [[String: Any]] = []
        Task { @MainActor in
            actions = AppActionRouter.catalog
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return jsonResponse(["count": actions.count, "actions": actions])
    }

    private func handleState() -> String {
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        let semaphore = DispatchSemaphore(value: 0)
        var state: [String: Any] = ["error": "state timed out"]
        Task { @MainActor in
            state = AppActionRouter.shared.snapshot(appState: appState)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)
        return jsonResponse(state)
    }

    private func handleAction(body: String) -> String {
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String, !action.isEmpty else {
            return jsonResponse(["error": "action is required"])
        }
        let params = (json["params"] as? [String: Any]) ?? [:]
        let semaphore = DispatchSemaphore(value: 0)
        var response: [String: Any] = ["error": "action timed out"]
        Task { @MainActor in
            do {
                let result = try await AppActionRouter.shared.perform(
                    action: action,
                    params: params,
                    appState: appState
                )
                response = ["ok": true, "action": action, "result": result]
            } catch {
                response = ["ok": false, "action": action, "error": error.localizedDescription]
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 660)
        return jsonResponse(response)
    }

    private func providersInfo() -> [String: Any] {
        guard __myCoderAppState != nil else { return ["error": "app not ready"] }
        var providers: [[String: Any]] = []
        
        // Web providers
        let webConfigs = WebProviderStore.load()
        for config in webConfigs {
            providers.append([
                "id": "web:\(config.id)",
                "name": config.displayName,
                "vendor": config.vendor.id,
                "isConnected": WebProviderConnectivity.isConnected(config, homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
                "models": config.allModels,
                "selectedModel": config.selectedModel
            ])
        }
        
        return ["providers": providers]
    }
    
    private func chatsInfo() -> [String: Any] {
        guard let appState = __myCoderAppState else { return ["error": "app not ready"] }
        let sessions = appState.sessions.map { session in
            [
                "id": session.id,
                "title": session.title,
                "directory": session.directory,
                "updatedAt": session.updatedAt.timeIntervalSince1970
            ]
        }
        return [
            "sessions": sessions,
            "selectedSessionId": appState.selectedSession?.id ?? "",
            "selectedProviderId": appState.selectedProviderID,
            "selectedModel": SendAPIResponseLogic.modelID(
                selectedModel: appState.selectedModel,
                effectiveModel: appState.effectiveSelectedModel()
            )
        ]
    }
    
    private func handleSend(body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else {
            return jsonResponse(["error": "message is required"])
        }
        
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        
        let chatId = json["chatId"] as? String
        let providerId = json["providerId"] as? String
        let modelId = json["modelId"] as? String

        // Round 29 R4: apply all @Published mutations on the main thread AND
        // wait for them here, so the HTTP response reports the post-mutation
        // state. The previous fire-and-forget version returned stale values:
        // for a new chat the response carried "" / the previously selected
        // session instead of the freshly created one.
        let semaphore = DispatchSemaphore(value: 0)
        var resolved: ResolvedSendTarget?
        Task { @MainActor in
            let target = Self.resolveSendTargets(appState: appState,
                                                 providerId: providerId,
                                                 modelId: modelId,
                                                 chatId: chatId,
                                                 message: message)
            NotificationCenter.default.post(
                name: Notification.Name("apiSendRequested"),
                object: nil,
                userInfo: ["message": message, "chatId": target.chatID]
            )
            resolved = target
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)

        guard let target = resolved else {
            return jsonResponse(["error": "send timed out waiting for main thread"])
        }
        return jsonResponse([
            "status": "sent",
            "message": message,
            "chatId": target.chatID,
            "providerId": target.providerID,
            "modelId": target.modelID
        ])
    }

    struct ResolvedSendTarget {
        let chatID: String
        let providerID: String
        let modelID: String
    }

    /// Applies provider/model selection, creates or selects the target session,
    /// and reads back the resulting state — all on the main actor. The returned
    /// triple is exactly what `/api/send` must echo to the client.
    @MainActor
    static func resolveSendTargets(appState: AppState,
                                   providerId: String?,
                                   modelId: String?,
                                   chatId: String?,
                                   message: String = "") -> ResolvedSendTarget {
        if let providerId = providerId {
            appState.selectProvider(providerId, persistPreference: false)
        }
        if let modelId = modelId, !modelId.isEmpty {
            appState.selectModel(modelId, persistPreference: false)
        }

        var targetSession: ChatSession?
        if let cid = chatId {
            // Audit 2026-09-09: resolve through the database as well — a
            // request arriving during startup (or for a persisted chat never
            // merged into memory) must hit the STORED chat, not spawn a
            // duplicate "API Chat".
            targetSession = appState.materializeSessionFromDatabase(id: cid)
        }
        if targetSession == nil {
            // Audit 2026-09-08: API chats used to be in-memory-only (temp
            // directory, never persisted) and vanished after restart. Create
            // a persisted standalone chat so it survives and shows in the
            // sidebar's Chats group (user directive 2026-09-08).
            targetSession = appState.createStandaloneSession(title: message.isEmpty ? "API Chat" : message)
        }
        if let session = targetSession {
            appState.selectedSession = session
        }

        return ResolvedSendTarget(
            chatID: appState.selectedSession?.id ?? "",
            providerID: appState.selectedProviderID,
            modelID: SendAPIResponseLogic.modelID(
                selectedModel: appState.selectedModel,
                effectiveModel: appState.effectiveSelectedModel()
            )
        )
    }
    
    private func messagesInfo() -> [String: Any] {
        guard let appState = __myCoderAppState else { return ["error": "app not ready"] }
        guard let sessionID = appState.selectedSession?.id else { return ["messages": []] }

        let messages = DatabaseBridge.shared.loadMessages(sessionId: sessionID)
        let result = messages.map { msg -> [String: Any] in
            var row: [String: Any] = [
                "id": msg.id,
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content,
                "isFinished": msg.isFinished,
                "isStreaming": msg.isStreaming
            ]
            // Route metadata chips (web-provider turns): header info the UI
            // renders above the answer; the content text stays clean
            // (user directive 2026-09-08).
            let chips = msg.parts.compactMap { part -> [String]? in
                if case .routeInfo(let chips) = part { return chips }
                return nil
            }.first ?? []
            if !chips.isEmpty {
                row["routeChips"] = chips
            }
            // Tool-call parts (web-agent loop): each spoiler in the UI.
            let toolParts: [[String: Any]] = msg.parts.compactMap { part -> [String: Any]? in
                guard case .toolCall(let name, let args, let result, let callID) = part else { return nil }
                var p: [String: Any] = [
                    "type": "toolCall",
                    "name": name,
                    "args": args
                ]
                if let result { p["result"] = result }
                if let callID { p["callID"] = callID }
                return p
            }
            if !toolParts.isEmpty {
                row["parts"] = toolParts
            }
            // Pending approval card (web agent): the interactive Allow/Deny
            // request the driver is waiting on.
            if let approvalID = msg.pendingApprovalID {
                row["pendingApproval"] = [
                    "id": approvalID,
                    "tool": msg.pendingApprovalTool ?? "",
                    "message": msg.pendingApprovalMessage ?? ""
                ]
            }
            return row
        }
        return ["messages": result, "sessionId": sessionID]
    }
    
    private func handleSelect(body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let appState = __myCoderAppState else {
            return jsonResponse(["error": "invalid body or app not ready"])
        }
        
        DispatchQueue.main.async {
            if let providerId = json["providerId"] as? String {
                appState.selectProvider(providerId, persistPreference: false)
            }
            if let modelId = json["modelId"] as? String {
                appState.selectModel(modelId, persistPreference: false)
            }
            if let chatId = json["chatId"] as? String {
                if let session = appState.sessions.first(where: { $0.id == chatId }) {
                    appState.selectedSession = session
                }
            }
        }
        
        return jsonResponse(["status": "selected"])
    }
    
    private func jsonResponse(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\n\r\n{\"error\":\"serialization failed\"}"
        }
        return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\n\r\n\(json)"
    }
    
    private func notFound() -> String {
        return "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\n\r\n{\"error\":\"not found\"}"
    }

    private func handleRefreshModels(body: String) -> String {
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerId = json["providerId"] as? String else {
            return jsonResponse(["error": "providerId required"])
        }
        let configs = WebProviderStore.load()
        guard let config = configs.first(where: { "web:\($0.id)" == providerId }) else {
            return jsonResponse(["error": "provider not found"])
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: String = "timeout"
        Task { @MainActor in
            // When the live page sits in the login webview (fresh manual
            // login), refresh THERE so discovery probes the hydrated page
            // instead of an about:blank default slot.
            let chatID = appState.debugWebviewURLs().contains(where: { $0.key.contains("provider-login::\(config.id)") && !$0.value.isEmpty && $0.value != "about:blank" })
                ? "provider-login"
                : nil
            result = await appState.refreshWebModels(for: config, chatID: chatID)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 180)
        let updated = WebProviderStore.load()
        let updatedConfig = updated.first(where: { $0.id == config.id })
        return jsonResponse(["message": result, "models": updatedConfig?.allModels ?? []])
    }

    private func handleEvaluate(body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let script = json["script"] as? String else {
            return jsonResponse(["error": "script is required"])
        }
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        // Optional target: run the script on a SPECIFIC webview key
        // (from GET /api/webviews) instead of the last-used one.
        let targetKey = json["webview"] as? String
        let semaphore = DispatchSemaphore(value: 0)
        var result: Any?
        Task { @MainActor in
            if let targetKey {
                result = await appState.debugEvaluateJS(script, webviewKey: targetKey)
            } else {
                result = await appState.debugEvaluateJS(script)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 15)
        if let result = result {
            if let dict = result as? [String: Any] {
                return jsonResponse(dict)
            } else if let arr = result as? [Any] {
                return jsonResponse(["result": arr])
            } else if let str = result as? String {
                return jsonResponse(["result": str])
            } else {
                return jsonResponse(["result": "\(result)"])
            }
        }
        return jsonResponse(["result": NSNull()])
    }

    private func handleWebviews() -> String {
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: String] = [:]
        Task { @MainActor in
            result = appState.debugWebviewURLs()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return jsonResponse(result)
    }

    private func handleSaveSession(body: String) -> String {
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerId = json["providerId"] as? String else {
            return jsonResponse(["error": "providerId required"])
        }
        let configs = WebProviderStore.load()
        guard let config = configs.first(where: { "web:\($0.id)" == providerId }) else {
            return jsonResponse(["error": "provider not found"])
        }
        let semaphore = DispatchSemaphore(value: 0)
        var cookies: [BrowserCookie] = []
        var errorRef: Error? = nil
        Task { @MainActor in
            let webView = appState.webView(for: config, projectID: "global", chatID: "provider-default")
            let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
            let selectors = WebVendorSelectors(
                input: catalogEntry?.input ?? "textarea, div[contenteditable='true']",
                sendButton: catalogEntry?.sendButton ?? "button[type='submit'], button[aria-label*='send']",
                responseContainer: catalogEntry?.responseContainer ?? "div[class*='markdown']",
                stopButton: catalogEntry?.stopButton ?? "button[aria-label*='stop']"
            )
            let bridge = WKWebViewBrowserBridge(webView: webView, selectors: selectors)
            do {
                cookies = try await bridge.cookies()
            } catch {
                errorRef = error
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)
        if let error = errorRef {
            return jsonResponse(["error": "failed to get cookies: \(error.localizedDescription)"])
        }
        guard !cookies.isEmpty else {
            return jsonResponse(["error": "no cookies found in browser"])
        }
        let sessionID = config.activeSessionID ?? WebSessionManager.defaultSessionID
        let store = WebSessionStore(
            cookies: cookies,
            localStorage: [:],
            savedAt: Date()
        )
        do {
            try WebSessionManager.persist(
                store,
                providerId: config.id,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                sessionID: sessionID
            )
            return jsonResponse(["status": "saved", "cookieCount": cookies.count])
        } catch {
            return jsonResponse(["error": "failed to save session: \(error.localizedDescription)"])
        }
    }

    private func handleInspect(body: String) -> String {
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        // Resolve the provider from the request body (providerId), falling
        // back to the first connected Kimi config for backwards compatibility.
        let json = body.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let requestedID = (json["providerId"] as? String) ?? (json["provider_id"] as? String)
        let configs = WebProviderStore.load()
        let normalized = requestedID?.replacingOccurrences(of: "web:", with: "")
        let config: WebProviderConfig
        if let normalized,
           let found = configs.first(where: { $0.id == normalized }) {
            config = found
        } else if let kimi = configs.first(where: { $0.vendor.id == "kimi" }) {
            config = kimi
        } else {
            return jsonResponse(["error": "provider not found"])
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var finalResult: [String: Any] = ["error": "timeout"]
        Task { @MainActor in
            do {
                let webView = appState.webView(for: config, projectID: "global", chatID: "provider-default")
                let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
                let selectors = WebVendorSelectors(
                    input: catalogEntry?.input ?? "textarea, div[contenteditable='true']",
                    sendButton: catalogEntry?.sendButton ?? "button[type='submit'], button[aria-label*='send']",
                    responseContainer: catalogEntry?.responseContainer ?? "div[class*='markdown']",
                    stopButton: catalogEntry?.stopButton ?? "button[aria-label*='stop']"
                )
                let bridge = WKWebViewBrowserBridge(webView: webView, selectors: selectors)
                
                // Restore cookies and navigate
                let sessionID = config.activeSessionID ?? WebSessionManager.defaultSessionID
                if let store = WebSessionManager.restore(providerId: config.id,
                                                         homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                                         sessionID: sessionID),
                   !store.cookies.isEmpty,
                   !WebSessionManager.isExpired(store) {
                    let payload = WebSessionRestorationLogic.payload(from: store)
                    try await bridge.setCookies(payload.cookies)
                    try await bridge.navigate(to: config.chatURL)
                    if !payload.localStorage.isEmpty {
                        try await bridge.setLocalStorage(payload.localStorage)
                        try await bridge.navigate(to: config.chatURL)
                    }
                }
                
                // Wait for input to be ready
                for _ in 0..<30 {
                    if try await bridge.exists(selector: selectors.input) {
                        break
                    }
                    await bridge.wait(ms: 500)
                }
                
                // Now run the inspection JS
                let js = """
                (function(){
                    var url = window.location.href;
                    var title = document.title;
                    var modelDropdown = document.querySelector('.current-model');
                    var modelDropdownText = modelDropdown ? modelDropdown.innerText.trim() : '';
                    var popover = document.querySelector('.models-popover, .n-popover__content');
                    var popoverOpen = !!popover;
                    var modelItems = Array.from(document.querySelectorAll('.model-item')).map(function(el){
                        var name = el.querySelector('.model-name .name');
                        var desc = el.querySelector('.desc');
                        var checked = el.classList.contains('checked');
                        return {name: name ? name.textContent.trim() : el.innerText.trim().substring(0, 50), desc: desc ? desc.textContent.trim() : '', checked: checked};
                    });
                    var effortValue = document.querySelector('.effort-value');
                    var effortTitle = document.querySelector('.effort-title');
                    var input = document.querySelector('.chat-input-editor, textarea, div[contenteditable="true"]');
                    var sendBtn = document.querySelector('.send-button-container, .chat-editor-action button[class*="send"], button[type="submit"]');
                    var newChatBtn = document.querySelector('.new-chat-btn, [class*="new-chat"]');
                    return JSON.stringify({url: url, title: title, modelDropdownText: modelDropdownText, popoverOpen: popoverOpen, modelItems: modelItems, effort: {value: effortValue ? effortValue.textContent.trim() : '', title: effortTitle ? effortTitle.textContent.trim() : ''}, input: input ? {tag: input.tagName, cls: input.className.substring(0, 80)} : null, sendButton: sendBtn ? {tag: sendBtn.tagName, cls: sendBtn.className.substring(0, 80)} : null, newChatButton: newChatBtn ? {tag: newChatBtn.tagName, cls: newChatBtn.className.substring(0, 80), text: newChatBtn.innerText.trim().substring(0, 50)} : null});
                })();
                """
                let inspectResult = await appState.debugEvaluateJS(js)
                if let jsonStr = inspectResult as? String,
                   let data = jsonStr.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    finalResult = dict
                } else {
                    finalResult = ["error": "failed to inspect"]
                }
            } catch {
                finalResult = ["error": "failed to inspect: \(error.localizedDescription)"]
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)
        return jsonResponse(finalResult)
    }

    private func handleDiscoverModels() -> String {
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        // Click model dropdown
        let clickScript = "document.querySelector('.current-model')?.click(); 'clicked'"
        let semaphore1 = DispatchSemaphore(value: 0)
        Task { @MainActor in
            _ = await appState.debugEvaluateJS(clickScript)
            semaphore1.signal()
        }
        _ = semaphore1.wait(timeout: .now() + 5)
        // Wait for popover
        Thread.sleep(forTimeInterval: 2)
        // Read model items
        let readScript = """
        (function(){
            var items = document.querySelectorAll('.model-item');
            var r = [];
            for (var i = 0; i < items.length; i++) {
                var el = items[i];
                var nameEl = el.querySelector('.model-name .name');
                var name = nameEl ? (nameEl.textContent || '').trim() : '';
                var desc = el.querySelector('.desc');
                var descText = desc ? desc.textContent.trim() : '';
                var checked = el.classList.contains('checked');
                if (name) r.push({name: name, desc: descText, checked: checked});
            }
            // Effort
            var effortEl = document.querySelector('.effort-value');
            var effort = effortEl ? effortEl.textContent.trim() : '';
            return JSON.stringify({models: r, effort: effort});
        })();
        """
        let semaphore2 = DispatchSemaphore(value: 0)
        var readResult: Any?
        Task { @MainActor in
            readResult = await appState.debugEvaluateJS(readScript)
            semaphore2.signal()
        }
        _ = semaphore2.wait(timeout: .now() + 5)
        if let jsonStr = readResult as? String,
           let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Save discovered models to config
            if let models = dict["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["name"] as? String }
                var configs = WebProviderStore.load()
                if let idx = configs.firstIndex(where: { $0.vendor.id == "kimi" }) {
                    var cfg = configs[idx]
                    cfg.discoveredModels = modelNames.map { WebProviderModel(name: $0) }
                    configs[idx] = cfg
                    WebProviderStore.save(configs)
                }
            }
            return jsonResponse(dict)
        }
        return jsonResponse(["error": "failed to read models"])
    }

    private func handleAddAccount(body: String) -> String {
        guard __myCoderAppState != nil else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vendorStr = json["vendor"] as? String,
              let vendor = WebChatVendor(rawValue: vendorStr) else {
            return jsonResponse(["error": "vendor required (kimi, qwen, chatgpt, claude)"])
        }
        var configs = WebProviderStore.load()
        // Find existing config for this vendor to clone settings from
        guard let existing = configs.first(where: { $0.vendor.id == vendorStr }) else {
            return jsonResponse(["error": "no existing config for vendor \(vendorStr)"])
        }
        // Create a new config with a different ID
        let newConfig = WebProviderConfig(
            id: UUID().uuidString,
            vendor: vendor,
            displayName: "\(existing.displayName) (Account \(configs.filter { $0.vendor.id == vendorStr }.count + 1))",
            transport: existing.transport,
            chatURL: existing.chatURL,
            systemPrompt: existing.systemPrompt,
            effort: existing.effort,
            toolCallDelayMs: existing.toolCallDelayMs,
            maxToolIterations: existing.maxToolIterations,
            acknowledgedToS: existing.acknowledgedToS
        )
        configs.append(newConfig)
        WebProviderStore.save(configs)
        return jsonResponse(["status": "added", "id": newConfig.id, "name": newConfig.displayName])
    }

    // MARK: - Web-provider debug endpoints (audit 2026-09-06)

    /// Creates the FIRST config for a vendor (the UI's "Add Kimi/Qwen/…"
    /// button). `add-account` clones an existing config; this endpoint covers
    /// the bootstrap case so the debug API can provision every vendor alone.
    private func handleAddVendor(body: String) -> String {
        guard __myCoderAppState != nil else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vendorStr = json["vendor"] as? String,
              let vendor = WebChatVendor(rawValue: vendorStr) else {
            return jsonResponse(["error": "vendor required (kimi, qwen, chatgpt, claude)"])
        }
        let configs = WebProviderStore.load()
        let outcome = WebAccountCloneLogic.next(for: vendor, in: configs)
        var updated = configs
        updated.append(outcome.config)
        WebProviderStore.save(updated)
        return jsonResponse([
            "status": outcome.isNewDefault ? "added" : "added-clone",
            "id": outcome.config.id,
            "name": outcome.config.displayName,
            "providerId": "web:\(outcome.config.id)",
            "chatURL": outcome.config.chatURL,
            "action": "now open /api/open-login and log in inside the app"
        ])
    }

    /// Shared resolution of a web provider config from "web:<id>" or raw id.
    private func webConfig(for providerId: String) -> WebProviderConfig? {
        let configs = WebProviderStore.load()
        let rawID = providerId.hasPrefix("web:")
            ? String(providerId.dropFirst(4))
            : providerId
        return configs.first { $0.id == rawID }
            ?? configs.first { $0.vendor.rawValue == rawID } // vendor name fallback
    }

    /// Opens the provider's login page in the app's embedded webview pool and
    /// reports whether the stored session is authenticated. When `login` is
    /// false the caller must log in manually in the app UI.
    private func handleWebLoginCheck(body: String) -> String {
        guard __myCoderAppState != nil else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerId = json["providerId"] as? String else {
            return jsonResponse(["error": "providerId required"])
        }
        guard let config = webConfig(for: providerId) else {
            return jsonResponse(["error": "web provider not found", "providerId": providerId])
        }
        let connected = WebProviderConnectivity.isConnected(
            config,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        let vendorConfigured = WebProviderStore.load().contains { $0.vendor == config.vendor }
        return jsonResponse([
            "providerId": "web:\(config.id)",
            "vendor": config.vendor.rawValue,
            "displayName": config.displayName,
            "configured": vendorConfigured,
            "connected": connected,
            "chatURL": config.chatURL,
            "selectedModel": config.selectedModel,
            "models": config.allModels,
            "sessionSaved": WebSessionManager.list(
                providerId: config.id,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            ).map { ["id": $0.id, "name": $0.name] },
            "action": connected ? "ready" : "open /api/open-login, log in inside the app, then POST /api/save-session"
        ])
    }

    /// Aggregated login/connectivity state for every configured web provider.
    private func handleWebLoginStatus() -> String {
        guard __myCoderAppState != nil else {
            return jsonResponse(["error": "app not ready"])
        }
        var result: [[String: Any]] = []
        for config in WebProviderStore.load() {
            result.append([
                "providerId": "web:\(config.id)",
                "vendor": config.vendor.rawValue,
                "displayName": config.displayName,
                "connected": WebProviderConnectivity.isConnected(
                    config,
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                ),
                "selectedModel": config.selectedModel,
                "modelCount": config.allModels.count
            ])
        }
        return jsonResponse(["providers": result])
    }

    /// Opens the provider's login screen in the app's webview pool so the user
    /// can log in manually. Returns immediately with the opened state; the
    /// caller polls /api/web-login-check or /api/webviews afterwards.
    private func handleOpenLogin(body: String) -> String {
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerId = json["providerId"] as? String else {
            return jsonResponse(["error": "providerId required"])
        }
        guard let config = webConfig(for: providerId) else {
            return jsonResponse(["error": "web provider not found", "providerId": providerId])
        }
        let semaphore = DispatchSemaphore(value: 0)
        var opened = false
        var url = ""
        Task { @MainActor in
            let webView = appState.webView(for: config, projectID: "global", chatID: "provider-login")
            let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
            let selectors = WebVendorSelectors(
                input: catalogEntry?.input ?? "textarea, div[contenteditable='true']",
                sendButton: catalogEntry?.sendButton ?? "button[type='submit']",
                responseContainer: catalogEntry?.responseContainer ?? "div[class*='markdown']",
                stopButton: catalogEntry?.stopButton ?? "button[aria-label*='stop']"
            )
            let bridge = WKWebViewBrowserBridge(webView: webView, selectors: selectors)
            do {
                // Restore saved cookies first, then land on the login page.
                let sessionID = config.activeSessionID ?? WebSessionManager.defaultSessionID
                if let store = WebSessionManager.restore(providerId: config.id,
                                                         homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                                         sessionID: sessionID),
                   !store.cookies.isEmpty {
                    let payload = WebSessionRestorationLogic.payload(from: store)
                    try await bridge.setCookies(payload.cookies)
                }
                let loginURL = (try? WebProviderCatalog.loadBundled().loginURL(for: config.vendor.id))
                    ?? config.chatURL
                try await bridge.navigate(to: loginURL)
                url = loginURL
                opened = true
            } catch {
                opened = false
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)
        return opened
            ? jsonResponse(["status": "opened", "url": url,
                            "note": "log in inside the myCoder window, then POST /api/save-session and re-check"])
            : jsonResponse(["error": "failed to open login page"])
    }

    /// Updates a web provider's chatURL (e.g. kimi.com → kimi.ai for
    /// non-CN accounts, or a vendor region change) without recreating the
    /// config and losing the saved session/models.
    private func handleUpdateProviderURL(body: String) -> String {
        guard __myCoderAppState != nil else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerId = json["providerId"] as? String,
              let chatURL = json["chatURL"] as? String,
              !chatURL.isEmpty else {
            return jsonResponse(["error": "providerId and chatURL required"])
        }
        guard let config = webConfig(for: providerId) else {
            return jsonResponse(["error": "web provider not found", "providerId": providerId])
        }
        var updated = config
        updated.chatURL = chatURL
        let stored = WebProviderStore.upsert(updated, in: WebProviderStore.load())
        WebProviderStore.save(stored)
        return jsonResponse([
            "status": "updated",
            "providerId": "web:\(updated.id)",
            "chatURL": updated.chatURL,
            "vendor": updated.vendor.rawValue
        ])
    }

    /// Sets a web provider's selected model (debug contract: switch models
    /// without the settings UI). The model must be in the provider's known
    /// list, otherwise the send flow would block on injection.
    private func handleSetWebModel(body: String) -> String {
        guard __myCoderAppState != nil else {
            return jsonResponse(["error": "app not ready"])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerId = json["providerId"] as? String,
              let model = (json["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty else {
            return jsonResponse(["error": "providerId and model required"])
        }
        guard var config = webConfig(for: providerId) else {
            return jsonResponse(["error": "web provider not found", "providerId": providerId])
        }
        guard config.allModels.contains(model) else {
            return jsonResponse([
                "error": "model not in provider list",
                "model": model,
                "models": config.allModels
            ])
        }
        config.selectedModel = model
        let stored = WebProviderStore.upsert(config, in: WebProviderStore.load())
        WebProviderStore.save(stored)
        return jsonResponse([
            "status": "updated",
            "providerId": "web:\(config.id)",
            "selectedModel": config.selectedModel
        ])
    }

    /// Sends a message like /api/send, then polls the target session's
    /// messages until the assistant turn finishes (bounded wait) and returns
    /// the conversation tail. This is the debug contract for "ask every
    /// provider a question and compare the answer".
    private func handleSendAndWait(body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else {
            return jsonResponse(["error": "message is required"])
        }
        guard let appState = __myCoderAppState else {
            return jsonResponse(["error": "app not ready"])
        }
        let providerId = json["providerId"] as? String
        let modelId = json["modelId"] as? String
        let timeoutSec = (json["timeoutSec"] as? Int) ?? 180

        // Resolve target + post the send exactly like /api/send.
        let resolveSemaphore = DispatchSemaphore(value: 0)
        var target: ResolvedSendTarget?
        Task { @MainActor in
            let t = Self.resolveSendTargets(appState: appState,
                                             providerId: providerId,
                                             modelId: modelId,
                                             chatId: json["chatId"] as? String,
                                             message: message)
            NotificationCenter.default.post(
                name: Notification.Name("apiSendRequested"),
                object: nil,
                userInfo: ["message": message, "chatId": t.chatID]
            )
            target = t
            resolveSemaphore.signal()
        }
        _ = resolveSemaphore.wait(timeout: .now() + 30)
        guard let target else {
            return jsonResponse(["error": "send timed out waiting for main thread"])
        }

        // Poll messages until the last assistant message finishes.
        // Audit 2026-09-08: internal UI status lines ("Thinking…", "Sent via …",
        // captcha/session notices) are NOT answers. Only content the vendor
        // actually produced completes the turn — the same contract the chat UI
        // enforces via WebSendCompletionLogic.
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSec))
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 1.5)
            let messages = DatabaseBridge.shared.loadMessages(sessionId: target.chatID)
            if let last = messages.last,
               last.role == .assistant,
               last.isFinished,
               !last.content.isEmpty,
               SendWaitAnswerLogic.isRealAnswer(last.content) {
                let tail = messages.suffix(4).map { msg in
                    [
                        "role": msg.role == .user ? "user" : "assistant",
                        "content": String(msg.content.prefix(2000)),
                        "isFinished": msg.isFinished
                    ] as [String: Any]
                }
                return jsonResponse([
                    "status": "answered",
                    "chatId": target.chatID,
                    "providerId": target.providerID,
                    "modelId": target.modelID,
                    "messages": tail
                ])
            }
            // A visible error message also completes the turn.
            if let last = messages.last, last.role == .assistant, last.isFinished,
               last.content.hasPrefix("myCoder Auto Free error:")
                   || last.content.hasPrefix("Web chat was not sent")
                   || last.content.hasPrefix("Web provider error:") {
                return jsonResponse([
                    "status": "error",
                    "chatId": target.chatID,
                    "providerId": target.providerID,
                    "modelId": target.modelID,
                    "error": String(last.content.prefix(1000)),
                    "messages": messages.suffix(2).map { ["role": $0.role == .user ? "user" : "assistant", "content": String($0.content.prefix(1000))] as [String: Any] }
                ])
            }
        }
        return jsonResponse([
            "status": "timeout",
            "chatId": target.chatID,
            "providerId": target.providerID,
            "modelId": target.modelID,
            "note": "no finished assistant message within \(timeoutSec)s — check /api/messages and /api/webviews"
        ])
    }
}
