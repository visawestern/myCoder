import Foundation

extension MyCoderAPIServer {
    // MARK: - Screenshot API

    /// GET /api/screenshot — capture the app's own window (no Screen Recording
    /// permission needed) and return it as PNG. Supports `?path=/abs/out.png`
    /// to write to a file instead of returning base64.
    func handleScreenshot(query: String = "") async -> String {
        let requestedPath = query.components(separatedBy: "&")
            .first(where: { $0.hasPrefix("path=") })
            .flatMap { String($0.dropFirst("path=".count)) }
            .map { ($0 as NSString).expandingTildeInPath }
        let result = await Self.mainRead { () -> [String: Any] in
            guard let shot = AppWindowCapture.capture() else {
                return ["ok": false, "error": "no visible window content to capture"]
            }
            let target: URL
            if let requestedPath {
                target = URL(fileURLWithPath: requestedPath)
            } else {
                target = AppWindowCapture.defaultURL()
            }
            do {
                try AppWindowCapture.write(shot, to: target)
                return [
                    "ok": true,
                    "method": shot.method,
                    "width": shot.width,
                    "height": shot.height,
                    "windowTitle": shot.windowTitle,
                    "path": target.path,
                    "base64": shot.pngData.base64EncodedString()
                ]
            } catch {
                return ["ok": false, "error": "capture failed: \(error.localizedDescription)"]
            }
        }
        return jsonResponse(result)
    }

    func handleRefreshModels(body: String) async -> String {
        guard let appState = await Self.mainRead({ __myCoderAppState }) else {
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
        // Когда живая страница сидит во вкладке логина (свежий ручной
        // вход), обновляем модели там — чтобы discovery зондировал
        // гидратированную страницу, а не about:blank.
        var chatID: String?
        for (key, bridge) in await AntiBrowserTabManager.shared.allBridges()
        where key.contains("provider-login::\(config.id)") {
            if let url = try? await bridge.currentURL(),
               !url.isEmpty, url != "about:blank" {
                chatID = "provider-login"
                break
            }
        }
        let result = await appState.refreshWebModels(for: config, chatID: chatID)
        let updated = WebProviderStore.load()
        let updatedConfig = updated.first(where: { $0.id == config.id })
        return jsonResponse(["message": result, "models": updatedConfig?.allModels ?? []])
    }

    /// Возвращает мост вкладки провайдера (provider-default) или nil,
    /// если движок не готов.
    @MainActor
    func engineBridge(forProviderID id: String?, fallbackVendor: String? = nil) -> AntiBrowserAutomationBridge? {
        guard (try? EngineStatusCenter.shared.requireEngine()) != nil else { return nil }
        var providerID = id ?? ""
        if providerID.hasPrefix("web:") {
            providerID = String(providerID.dropFirst(4))
        }
        if providerID.isEmpty, let fallbackVendor {
            providerID = WebProviderStore.load().first(where: { $0.vendor.id == fallbackVendor })?.id ?? ""
        }
        guard !providerID.isEmpty else { return nil }
        let key = AntiBrowserTabManager.makeKey(providerID: providerID,
                                               projectID: "global",
                                               chatID: "provider-default")
        return AntiBrowserTabManager.shared.bridge(tabKey: key)
    }

    func handleEvaluate(body: String) async -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let script = json["script"] as? String else {
            return jsonResponse(["error": "script is required"])
        }
        let targetKey = json["webview"] as? String
        var result: Any?
        if let bridge = await engineBridge(forProviderID: targetKey) {
            result = try? await bridge.evaluateJS(script)
        }
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

    func handleWebviews() async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
            return jsonResponse(["error": "app not ready"])
        }
        var result: [String: String] = [:]
        for (key, bridge) in await AntiBrowserTabManager.shared.allBridges() {
            result[key] = (try? await bridge.currentURL()) ?? ""
        }
        return jsonResponse(result)
    }

    /// POST /api/save-session — живая проверка вкладки провайдера. Раньше здесь
    /// копировались cookie в файлы; теперь сохраняется только отметка
    /// подтверждённого входа, а сессию хранит постоянный профиль AntiBrowser.
    func handleSaveSession(body: String) async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
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
        let tabKey = AntiBrowserTabManager.makeKey(providerID: config.id,
                                                   projectID: "global",
                                                   chatID: "provider-default")
        let bridge = await AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
        do {
            let cookies = try await bridge.cookies()
            let pageText = (try? await bridge.pageText()) ?? ""
            let verdict = WebLoginVerificationLogic.verdict(
                vendor: config.vendor,
                cookies: cookies,
                pageText: pageText
            )
            guard verdict == .confirmed else {
                return jsonResponse(["error": WebLoginVerificationLogic.message(for: verdict)])
            }
            var updated = config
            updated.loginConfirmedAt = Date()
            WebProviderStore.save(WebProviderStore.upsert(updated, in: configs))
            return jsonResponse(["status": "confirmed", "cookieCount": cookies.count])
        } catch {
            return jsonResponse(["error": "failed to verify login: \(error.localizedDescription)"])
        }
    }

    func handleInspect(body: String) async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
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
        
        var finalResult: [String: Any] = ["error": "timeout"]
        do {
            let tabKey = AntiBrowserTabManager.makeKey(providerID: config.id,
                                                      projectID: "global",
                                                      chatID: "provider-default")
            let bridge = await AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
            let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
            let selectors = WebVendorSelectors(
                input: catalogEntry?.input ?? "textarea, div[contenteditable='true']",
                sendButton: catalogEntry?.sendButton ?? "button[type='submit'], button[aria-label*='send']",
                responseContainer: catalogEntry?.responseContainer ?? "div[class*='markdown']",
                stopButton: catalogEntry?.stopButton ?? "button[aria-label*='stop']"
            )
            
            // The login lives in the persistent AntiBrowser profile; make sure
            // the tab shows the provider's page instead of restoring cookies.
            let currentURL = (try? await bridge.currentURL()) ?? ""
            if currentURL.isEmpty || currentURL == "about:blank" {
                try await bridge.navigate(to: config.chatURL)
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
            let inspectResult = try await bridge.evaluateJS(js)
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
        return jsonResponse(finalResult)
    }

    func handleDiscoverModels() async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
            return jsonResponse(["error": "app not ready"])
        }
        // Click model dropdown
        let clickScript = "document.querySelector('.current-model')?.click(); 'clicked'"
        let bridge = await engineBridge(forProviderID: nil, fallbackVendor: "kimi")
        if let bridge {
            _ = try? await bridge.evaluateJS(clickScript)
        }
        // Wait for popover
        try? await Task.sleep(nanoseconds: 2_000_000_000)
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
        var readResult: Any?
        if let bridge {
            readResult = try? await bridge.evaluateJS(readScript)
        }
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

    func handleAddAccount(body: String) async -> String {
        guard await Self.mainRead({ __myCoderAppState != nil }) else {
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
}
