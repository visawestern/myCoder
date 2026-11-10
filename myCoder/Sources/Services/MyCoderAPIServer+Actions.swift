import Foundation

extension MyCoderAPIServer {
    func handleActions() -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var actions: [[String: Any]] = []
        Task { @MainActor in
            actions = AppActionRouter.catalog
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return jsonResponse(["count": actions.count, "actions": actions])
    }

    /// Read-only diagnostic: reports the CURRENT mouse cursor identity
    /// (NSCursor.current), the mouse position, and the view chain under the
    /// pointer for every visible window. Used to verify cursor behavior in the
    /// running app (e.g. I-beam over the composer) without guessing.
    func handleCursorDebug() -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any] = ["error": "timed out"]
        Task { @MainActor in
            result = CursorDiagnostics.snapshot()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return jsonResponse(result)
    }

    func handleState() -> String {
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

    func handleAction(body: String) -> String {
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

    func providersInfo() -> [String: Any] {
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
    
    func chatsInfo() -> [String: Any] {
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
    
    func handleSend(body: String) -> String {
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
            // a persisted chat so it survives and shows in the sidebar.
            // Live run 2026-11-03: an OPEN PROJECT must produce a project
            // chat, otherwise the working directory falls back to home and the
            // model is told `cwd: /Users/apple` while the context pack lists
            // project files — it then answers "project not in current
            // directory" and searches the whole disk.
            let plan = SendTargetPlanLogic.plan(
                chatId: chatId,
                selectedWorkspace: appState.selectedWorkspace
            )
            if plan.createsStandalone {
                targetSession = appState.createStandaloneSession(
                    title: message.isEmpty ? "API Chat" : message
                )
            } else if let workspace = appState.selectedWorkspace {
                targetSession = appState.createProjectSession(
                    in: workspace,
                    title: message.isEmpty ? "API Chat" : message
                )
            } else {
                targetSession = appState.createStandaloneSession(
                    title: message.isEmpty ? "API Chat" : message
                )
            }
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
    
    func messagesInfo() -> [String: Any] {
        guard let appState = __myCoderAppState else { return ["error": "app not ready"] }
        guard let sessionID = appState.selectedSession?.id else { return ["messages": []] }

        let messages = DatabaseBridge.shared.loadMessages(sessionId: sessionID)
        let result = messages.map { msg -> [String: Any] in
            var row = MessageAPIRowLogic.row(for: msg)
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
    
    func handleSelect(body: String) -> String {
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
    
    func jsonResponse(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\n\r\n{\"error\":\"serialization failed\"}"
        }
        return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\n\r\n\(json)"
    }
    
    func notFound() -> String {
        return "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\n\r\n{\"error\":\"not found\"}"
    }
}
