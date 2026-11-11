import Foundation

extension WebChatDriver {
    /// Start a new chat session by clicking the "New Chat" button.
    /// Returns the new chat URL or nil if could not determine.
    func startNewSession() async throws -> String? {
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)

        // Try exact interactive controls only. A fuzzy div click can select a
        // history row or page heading and silently keep the old remote chat.
        let beforeURL = try? await bridge.currentURL()
        let beforeID = try? await getCurrentChatID()
        let newChatTexts = catalogEntry?.newChatTexts ?? ["New Chat", "Новый чат", "New chat", "Начать", "新对话"]
        for text in newChatTexts {
            let clicked = (try? await bridge.clickVisibleTextExact(selector: "button, a, [role='button'], [role='menuitem']", text: text)) ?? false
            guard clicked else { continue }
            await bridge.wait(ms: 2000)
            let afterURL = try await bridge.currentURL()
            let afterID = try? await getCurrentChatID()
            guard afterURL != beforeURL || afterID != beforeID,
                  afterID?.isEmpty == false else { continue }
            return afterURL
        }
        // Fallback: try clicking catalog-specific newChatSelector (e.g. ".new-chat-btn")
        if let newChatSel = catalogEntry?.newChatSelector {
            let clicked = (try? await bridge.click(selector: newChatSel)) != nil
            if clicked {
                await bridge.wait(ms: 2000)
                let afterURL = try await bridge.currentURL()
                let afterID = try? await getCurrentChatID()
                if afterURL != beforeURL || afterID != beforeID {
                    return afterURL
                }
            }
        }
        // Final fallback: try clicking any element with "new-chat" in class
        if (try? await bridge.click(selector: "[class*='new-chat']")) != nil {
            await bridge.wait(ms: 2000)
            let afterURL = try await bridge.currentURL()
            if afterURL != beforeURL {
                return afterURL
            }
        }
        return nil
    }

    /// Extract the chat ID/slug from the current URL or the provider's active
    /// conversation DOM. Kimi can keep the shell at `/` while exposing the
    /// active UUID through data attributes/history links, so URL-only parsing
    /// incorrectly blocked every first send.
    func getCurrentChatID() async throws -> String? {
        let url = try await bridge.currentURL()
        // Kimi/Qwen: /chat/{id}; ChatGPT: /c/{id}.
        let patterns = ["/chat/", "/c/"]
        for pattern in patterns {
            if let range = url.range(of: pattern) {
                let after = url[range.upperBound...]
                let pathPart = after.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first.map(String.init) ?? String(after)
                if let chatID = WebRemoteChatIdentityLogic.firstValid([pathPart]) {
                    return chatID
                }
            }
        }

        let script = """
        (function(){
          const values = [];
          const selectors = [
            '[data-chat-id]', '[data-conversation-id]', '[data-conversationid]',
            '[data-testid*="conversation" i]', '[aria-current="page"]',
            'a[href*="/chat/"]', 'a[href*="/c/"]'
          ];
          selectors.forEach(selector => document.querySelectorAll(selector).forEach(el => {
            // Audit 2026-09-08 (ChatGPT): `data-testid` VALUES are turn-level
            // keys ("conversation-turn-2", "conversation-options-button"),
            // never the conversation id — reading them bound a turn key as
            // the chat. The selector still FINDS candidate elements; only
            // id-carrying attributes are read.
            ['data-chat-id', 'data-conversation-id', 'data-conversationid', 'href'].forEach(attr => {
              const value = el.getAttribute(attr);
              if (!value) return;
              if (attr === 'href') {
                // Audit 2026-09-08: Kimi sidebar hrefs end with
                // "?chat_enter_method=history" — taking the LAST path segment
                // yielded the query literal ("history") and masked the real
                // id. Emit EVERY path segment and let the validator pick the
                // first id-shaped one (query segments are rejected there).
                const parts = value.split(/[\\/?#]/).filter(Boolean);
                parts.forEach(part => values.push(part));
              } else {
                values.push(value);
              }
            });
          }));
          return JSON.stringify(values);
        })();
        """
        let raw = try await bridge.evaluateJS(script)
        let candidates: [String]
        if let json = raw as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            candidates = decoded
        } else if let decoded = raw as? [String] {
            candidates = decoded
        } else {
            candidates = []
        }
        return WebRemoteChatIdentityLogic.firstValid(candidates)
    }

    /// Select a model in the web UI.
    func selectModel(_ modelName: String) async throws {
        let selector = try modelSelector()
        // Click model button
        try await bridge.click(selector: selector)
        // Wait for dropdown
        try await bridge.waitForSelector(selector: "div.model-item, [class*='model-item']", timeout: 5000)
        // Find and click matching model
        let clicked = try await bridge.clickVisibleTextExact(
            selector: "div.model-item, [class*='model-item'], [role='option'], [role='menuitem']",
            text: modelName
        )
        if !clicked {
            throw WebChatError.modelNotFound(L.t(AppLocalizationKey.locWebModelNotFound).replacingOccurrences(of: "{0}", with: modelName))
        }
        await bridge.wait(ms: 500)
    }

    /// Select a mode (auto/think/fast/image).
    func selectMode(_ mode: String) async throws {
        switch config.vendor {
        case .qwen:
            try await bridge.click(selector: "[class*='mode-select']")
            try await bridge.waitForSelector(selector: ".ant-select-item-option", timeout: 5000)
            let clicked = try await bridge.clickByText(
                selector: ".ant-select-item-option-content",
                text: mode
            )
            if !clicked { throw WebChatError.modeNotFound(mode) }
        case .kimi:
            // Kimi modes are in sidebar
            let clicked = try await bridge.clickByText(
                selector: "a, button, [role='button']",
                text: mode
            )
            if !clicked { throw WebChatError.modeNotFound(mode) }
        default:
            break
        }
        await bridge.wait(ms: 500)
    }

    /// Select thinking/effort level.
    func selectThinking(_ level: WebEffort) async throws {
        // Round 30b: try live menu labels first, legacy fallbacks after.
        let labels = effortCandidates(for: level) ?? [level.displayName]
        switch config.vendor {
        case .qwen:
            try await bridge.click(selector: ".qwen-thinking-selector .qwen-chat-v2-dropdown-menu-trigger, .qwen-thinking-selector")
            try? await bridge.waitForSelector(selector: ".qwen-chat-v2-dropdown-menu-item, .ant-select-item-option", timeout: 5000)
            var clicked = false
            for label in labels where !clicked {
                clicked = try await bridge.clickByText(
                    selector: ".qwen-chat-v2-dropdown-menu-item, .ant-select-item-option-content",
                    text: label
                )
            }
            if !clicked { throw WebChatError.effortNotFound(labels.first ?? "") }
        case .kimi:
            try await bridge.click(selector: "[class*='effort']")
            try await bridge.waitForSelector(selector: "[class*='effort-option'], [role='option']", timeout: 5000)
            var kimiClicked = false
            for candidate in labels where !kimiClicked {
                kimiClicked = try await bridge.clickByText(
                    selector: "[class*='effort-option'], [role='option']",
                    text: candidate
                )
            }
            if !kimiClicked { throw WebChatError.effortNotFound(labels.first ?? "") }
        default:
            break
        }
        await bridge.wait(ms: 500)
    }

    /// Resolve the model selector for the current vendor.
    func modelSelector() throws -> String {
        if let custom = config.customModelSelector, !custom.isEmpty { return custom }
        if let catalog = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id),
           let button = catalog.modelButton?.trimmingCharacters(in: .whitespacesAndNewlines),
           !button.isEmpty {
            return button
        }
        throw WebChatError.noModelSelector
    }

    /// Map a WebEffort to a vendor-specific label for matching in the dropdown.
    /// Round 30b: right after a verified SmartSend submission the page is still
    /// navigating to its remote chat URL; the model/effort DOM may be mid-reload
    /// and a single immediate injection pass races against it. Wait until the
    /// location has stopped changing before touching vendor menus.
    func waitForPageURLStability(maxMs: Int = 6000) async {
        var last = (try? await bridge.currentURL()) ?? ""
        var stableReads = 0
        let start = Date()
        while Date().timeIntervalSince(start) * 1000 < Double(maxMs) {
            await bridge.wait(ms: 300)
            let now = (try? await bridge.currentURL()) ?? last
            if now == last {
                stableReads += 1
                if stableReads >= 2 { return }
            } else {
                last = now
                stableReads = 0
            }
        }
    }

    func effortCandidates(for effort: WebEffort) -> [String]? {
        switch config.vendor {
        case .kimi:
            switch effort {
            case .low: return ["快"]
            case .medium: return ["标准"]
            case .high: return ["深度思考"]
            }
        case .qwen:
            // Round 30b: live menu renders English items ("Auto"/"Think"/"Fast");
            // legacy Chinese labels kept as fallbacks for older locales.
            switch effort {
            case .low: return ["Fast", "快"]
            case .medium: return ["Auto", "标准"]
            case .high: return ["Think", "深度思考"]
            }
        case .chatgpt:
            switch effort {
            case .low: return ["low"]
            case .medium: return ["medium"]
            case .high: return ["high"]
            }
        case .claude:
            // Live 2026 Claude UI exposes an Effort submenu inside the model
            // menu ("Effort: Max"); the tiers map to low/medium/high.
            switch effort {
            case .low: return ["Low", "Низкий"]
            case .medium: return ["Medium", "Средний"]
            case .high: return ["Max", "High", "Высокий", "Максимум"]
            }
        case .custom:
            return nil
        }
    }

    func antiBanDelay() async {
        let ms = WebAntiBanTiming.delayMs(base: config.toolCallDelayMs, randomUnit: randomUnit())
        if ms > 0 { await bridge.wait(ms: ms) }
    }
}
