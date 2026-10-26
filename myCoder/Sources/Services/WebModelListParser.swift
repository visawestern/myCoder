import Foundation

/// Extracts the real model list from a vendor's web model-dropdown
/// (plan Раздел 13 п.4). The browser layer reads the dropdown's option texts
/// (via BrowserAutomationBridge.readText on the model-dropdown selector) and
/// passes them here; this pure logic cleans/normalizes them into model ids.
/// No hardcoded guesses — if parsing yields nothing, the caller keeps the empty
/// list and the UI falls back to vendor defaults only as a last resort.
enum WebModelListParser {
    /// Parse newline/pipe-separated option labels captured from the dropdown
    /// into a de-duplicated, ordered list of model names.
    static func parse(dropdownText: String, vendor: WebChatVendor) -> [String] {
        let separators = CharacterSet(charactersIn: "\n|,")
        let rawTokens = dropdownText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var seen = Set<String>()
        var result: [String] = []
        for token in rawTokens {
            guard let name = normalize(token, vendor: vendor) else { continue }
            if seen.contains(name.lowercased()) { continue }
            seen.insert(name.lowercased())
            result.append(name)
        }
        if vendor == .chatgpt {
            return result.filter { isChatGPTModelLabel($0) }
        }
        return result
    }

    /// Normalize a single dropdown label into a model name, or nil if it's UI
    /// chrome (checkmarks, "New", "Upgrade", empty, badges).
    static func normalize(_ raw: String, vendor: WebChatVendor) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Strip leading selection markers / emojis commonly present in web menus.
        for prefix in ["✓", "✔", "•", "- ", "* "] {
            if s.hasPrefix(prefix) { s.removeFirst(prefix.count); s = s.trimmingCharacters(in: .whitespaces) }
        }
        guard isValidModelLabel(s, vendor: vendor) else { return nil }
        return s
    }

    /// Validate a label before it can enter a persisted web model catalog.
    /// Raw text parsing is intentionally conservative; structured DOM discovery
    /// additionally requires a visible selectable leaf option.
    static func isValidModelLabel(_ raw: String, vendor: WebChatVendor) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !normalized.isEmpty, normalized.count <= 80,
              normalized.rangeOfCharacter(from: .letters) != nil else { return false }

        let lower = normalized.lowercased()
        let compact = lower.replacingOccurrences(of: "[^a-z0-9а-яё]", with: "", options: .regularExpression)
        let exactNoise: Set<String> = [
            "new", "upgrade", "plus", "pro plan", "manage", "settings", "see all",
            "more", "more models", "expand more", "expand more models", "coming soon",
            "beta", "sign in", "log in", "model", "model comparison", "all models",
            "models", "model selector", "model settings", "select model", "choose model",
            "авто", "мышление", "глубокое мышление", "размышление",
            "fast", "quick", "auto", "thinking", "deep thinking", "reasoning", "effort"
        ]
        guard !exactNoise.contains(lower) else { return false }
        let rejectedFragments = [
            "model comparison", "all models", "expand more", "show more", "more models",
            "select model", "choose model", "upgrade", "settings", "sign in", "log in"
        ]
        guard !rejectedFragments.contains(where: { lower.contains($0) }) else { return false }
        guard !compact.allSatisfy({ $0.isNumber }) else { return false }

        switch vendor {
        case .qwen:
            // Qwen's selectable labels are compact family IDs. Descriptions can
            // mention Qwen3 too, so require a model-shaped token and reject
            // sentence-like labels from broad DOM scans.
            let words = normalized.split(separator: " ").count
            let modelShape = lower.range(of: "\\bqwen(?:coder)?[ -]?[0-9]", options: .regularExpression) != nil
                || lower.range(of: "\\bqwen[ -]?(?:max|plus|turbo|long|coder|vl)\\b", options: .regularExpression) != nil
            return words <= 4 && modelShape && !lower.contains(". ") && !lower.contains(",")
        case .kimi:
            // Kimi exposes Instant(Быстрый) / K3 / K3 Swarm family labels;
            // effort labels and prose are rejected before persistence.
            // Supports both English and Russian UI labels.
            let words = normalized.split(separator: " ").count
            let modelShape = lower.contains("kimi") || lower.contains("moonshot")
                || lower.contains("instant") || lower.contains("быстр")
                || lower.contains("k3") || lower.contains("k2")
                || lower.range(of: "\\bk[0-9]", options: .regularExpression) != nil
            return words <= 4 && modelShape && !lower.contains(". ") && !lower.contains(",")
        case .chatgpt:
            return isChatGPTModelLabel(normalized)
        case .claude:
            // Claude model family labels (live 2026 menu): "Fable 5.1",
            // "Opus 5", "Sonnet 5", "Haiku 4.5", "Opus 4.8". Effort labels
            // ("Effort", "Max") and prose are rejected before persistence.
            let words = normalized.split(separator: " ").count
            let modelShape = lower.contains("claude") || lower.contains("opus")
                || lower.contains("sonnet") || lower.contains("haiku")
                || lower.contains("fable")
                || lower.range(of: "\\b(opus|sonnet|haiku|fable)\\b ?[0-9]", options: .regularExpression) != nil
            return words <= 4 && modelShape && !lower.contains(". ") && !lower.contains(",")
        case .custom:
            // Custom sites cannot be safely inferred from arbitrary text. Keep
            // only labels that resemble a versioned/provider model ID.
            return lower.range(of: "[a-z][a-z0-9._:-]*[0-9]", options: .regularExpression) != nil
                || lower.contains("gpt") || lower.contains("claude") || lower.contains("llama")
        }
    }

    /// ChatGPT's model switcher can contain feature actions beside model
    /// options. Keep those actions out of the composer model list.
    /// The pattern is STRICT by design: arbitrary sentences merely CONTAINING
    /// "gpt" (e.g. the chat-history title "Лимиты ChatGPT Pro для кодинга"
    /// scraped from the sidebar during a 2026-UI discovery) must never
    /// survive as model names. A ChatGPT model label is one of:
    /// "GPT-5.x" / "GPT-4.x" / "GPT-4o" family shapes, "o1"/"o3"/"o4"
    /// prefixes, the literal "auto", or "ChatGPT Auto" (the 2026 no-switcher
    /// fallback). Verbs/imperatives ("Закрепить…", "Открыть…") are rejected.
    private static func isChatGPTModelLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        if lower == "chatgpt" { return false }
        let featureLabels = [
            "deep research", "research", "image", "images", "canvas", "agent",
            "search", "study", "shopping", "tasks", "projects", "voice"
        ]
        if featureLabels.contains(where: { lower.contains($0) }) { return false }
        // Imperative UI verbs (RU/EN) mark buttons/menu commands, not models.
        let verbPrefixes = ["закрепить", "открыть", "удалить", "переименовать",
                             "поделиться", "архив", "pin", "open", "delete",
                             "rename", "share", "archive", "duplicate", "settings"]
        if verbPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }
        let words = lower.split(separator: " ").count
        guard words <= 4 else { return false }
        // "ChatGPT Auto" (mode fallback) is a valid synthetic label —
        // including the effort-qualified variants the discovery fallback
        // emits ("ChatGPT Auto (Reasoning)" / "(Instant)"), which must
        // survive sanitize or the provider ends up with zero models.
        if lower == "chatgpt auto" { return true }
        if lower == "chatgpt auto (reasoning)" { return true }
        if lower == "chatgpt auto (instant)" { return true }
        // Versioned family shapes: gpt-5.2, gpt-5, gpt-4o, gpt-4.1, o1, o3, o4.
        if lower.range(of: "\\bgpt-?[45][a-z0-9.]*", options: .regularExpression) != nil { return true }
        if lower.range(of: "^o[134](-[a-z0-9]+)?$", options: .regularExpression) != nil { return true }
        if lower == "auto" { return true }
        return false
    }

    
    /// Parse effort/thinking/reasoning levels from a dropdown text.
    static func parseEffortLevels(dropdownText: String, vendor: WebChatVendor) -> [WebEffort] {
        let separators = CharacterSet(charactersIn: "\n|,")
        let rawTokens = dropdownText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var seen = Set<WebEffort>()
        var result: [WebEffort] = []
        for token in rawTokens {
            guard let effort = normalizeEffort(token, vendor: vendor) else { continue }
            if seen.contains(effort) { continue }
            seen.insert(effort)
            result.append(effort)
        }
        return result
    }

    /// Normalize a single dropdown label into an effort level, or nil if it's UI chrome.
    static func normalizeEffort(_ raw: String, vendor: WebChatVendor) -> WebEffort? {
        normalizeEffortLabel(raw, vendor: vendor)
    }

    /// Explicit effort vocabulary. Unknown labels are rejected rather than
    /// silently mapped to `.medium`; this prevents model names and menu prose
    /// from appearing as a bogus effort control.
    static func normalizeEffortLabel(_ raw: String, vendor: WebChatVendor) -> WebEffort? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Strip leading selection markers / emojis commonly present in web menus.
        for prefix in ["✓", "✔", "•", "- ", "* "] {
            if s.hasPrefix(prefix) { s.removeFirst(prefix.count); s = s.trimmingCharacters(in: .whitespaces) }
        }
        let lower = s.lowercased()
        let compact = lower.replacingOccurrences(of: "[^a-zа-яё0-9一-龯]", with: "", options: .regularExpression)
        let isLow = ["low", "fast", "quick", "низк", "быстр", "快速", "快", "低"].contains { compact.contains($0) }
        let isHigh = ["high", "deep", "thinking", "reasoning", "высок", "глубок", "мышлен", "深度", "推理", "高"].contains { compact.contains($0) }
        let isMedium = ["medium", "standard", "стандарт", "default", "balanced", "auto", "средн", "обыч", "авто", "标准", "自动", "中"].contains { compact.contains($0) }

        // Vendor-specific controls share this vocabulary, but the final
        // fallback is intentionally nil for every vendor.
        switch vendor {
        case .kimi, .qwen, .chatgpt, .claude, .custom:
            if isHigh { return .high }
            if isLow { return .low }
            if isMedium { return .medium }
            return nil
        }
    }

    /// Merge freshly parsed models into a config, preserving user selection if
    /// still present (plan Раздел 13 п.4).
    static func updated(_ config: WebProviderConfig, withDropdownText text: String) -> WebProviderConfig {
        let modelNames = parse(dropdownText: text, vendor: config.vendor)
        let models = modelNames.map { WebProviderModel(name: $0) }
        return WebModelRefreshLogic.replacing(config: config, with: models)
    }
}
