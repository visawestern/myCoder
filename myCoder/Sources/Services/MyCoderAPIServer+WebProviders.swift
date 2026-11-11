import Foundation

extension MyCoderAPIServer {
    // MARK: - Web-provider debug endpoints (audit 2026-09-06)

    /// Creates the FIRST config for a vendor (the UI's "Add Kimi/Qwen/…"
    /// button). `add-account` clones an existing config; this endpoint covers
    /// the bootstrap case so the debug API can provision every vendor alone.
    func handleAddVendor(body: String) async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
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
    func webConfig(for providerId: String) -> WebProviderConfig? {
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
    func handleWebLoginCheck(body: String) async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
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
    func handleWebLoginStatus() async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
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
    func handleOpenLogin(body: String) async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
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
        let tabKey = AntiBrowserTabManager.makeKey(providerID: config.id,
                                                   projectID: "global",
                                                   chatID: "provider-login")
        let bridge = await AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
        var opened = false
        var url = ""
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
        return opened
            ? jsonResponse(["status": "opened", "url": url,
                            "note": "log in inside the myCoder window, then POST /api/save-session and re-check"])
            : jsonResponse(["error": "failed to open login page"])
    }

    /// Updates a web provider's chatURL (e.g. kimi.com → kimi.ai for
    /// non-CN accounts, or a vendor region change) without recreating the
    /// config and losing the saved session/models.
    func handleUpdateProviderURL(body: String) async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
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
    func handleSetWebModel(body: String) async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
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
}
