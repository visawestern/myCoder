import Foundation

extension WebModelDiscovery {
    /// Discover the vendor's real effort/thinking levels from the web UI.
    /// Returns nil if the effort dropdown isn't found or fails.
    static func discoverEffort(using bridge: BrowserAutomationBridge,
                              effortDropdownSelector: String,
                              vendor: WebChatVendor) async -> [WebEffort]? {
        let selectors = effortDropdownSelector
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for selector in selectors {
            do {
                var dropdownReady = false
                for _ in 0..<20 {
                    if (try? await bridge.exists(selector: selector)) == true {
                        dropdownReady = true
                        break
                    }
                    await bridge.wait(ms: 500)
                }
                let triggerTexts = (try? await readVisibleTexts(using: bridge, selector: selector)) ?? []
                guard dropdownReady, !triggerTexts.isEmpty else { continue }
                try await bridge.click(selector: selector)
                await bridge.wait(ms: 500)
                let triggerText = (try? await bridge.readText(selector: selector)) ?? ""
                let optionSelector = "[role='option'], [class*='effort'], [class*='thinking'], [class*='menu-item'], .ant-select-item-option-content, .effort-value, button"
                let optionText = (try? await bridge.readText(selector: optionSelector)) ?? ""
                let visibleText = ((try? await readVisibleTexts(using: bridge, selector: optionSelector)) ?? []).joined(separator: "\n")
                let text = [triggerText, optionText, visibleText].filter { !$0.isEmpty }.joined(separator: "\n")
                let efforts = WebModelListParser.parseEffortLevels(dropdownText: text, vendor: vendor)
                if !efforts.isEmpty { return efforts }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func readVisibleTexts(using bridge: BrowserAutomationBridge, selector: String) async throws -> [String] {
        let selectorJSON = (try? JSONSerialization.data(withJSONObject: [selector]))
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
        let result = try await bridge.evaluateJS("""
        Array.from(document.querySelectorAll(\(selectorJSON)))
            .filter(el => {
                const style = window.getComputedStyle(el);
                const rect = el.getBoundingClientRect();
                return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
            })
            .map(el => (el.innerText || el.textContent || '').trim())
            .filter(Boolean)
        """)
        if let values = result as? [String] {
            var seen = Set<String>()
            return values.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        return []
    }

    /// Discover feature modes (Deep Research, Create Image, etc.) for a vendor.
    static func discoverFeatureModes(using bridge: BrowserAutomationBridge,
                                     vendor: WebChatVendor) async -> [FeatureMode] {
        var modes: [FeatureMode] = []
        switch vendor {
        case .qwen:
            modes = await discoverQwenFeatureModes(bridge: bridge)
        case .kimi:
            modes = await discoverKimiFeatureModes(bridge: bridge)
        default:
            break
        }
        return modes
    }

    /// Discover Qwen feature modes via mode-select dropdown.
    private static func discoverQwenFeatureModes(bridge: BrowserAutomationBridge) async -> [FeatureMode] {
        do {
            try await bridge.click(selector: "[class*='mode-select']")
            try await bridge.waitForSelector(selector: ".ant-select-item-option", timeout: 5000)

            let rawModes = try await bridge.evaluateJS("""
                Array.from(document.querySelectorAll('.ant-select-item-option-content'))
                    .map(el => ({
                        name: el.textContent.trim(),
                        disabled: el.closest('.ant-select-item')?.classList.contains('ant-select-item-disabled') ?? false
                    }))
            """) as? [[String: Any]] ?? []

            return rawModes.compactMap { dict in
                guard let name = dict["name"] as? String, !name.isEmpty else { return nil }
                return FeatureMode(name: name, icon: iconForMode(name), isEnabled: !(dict["disabled"] as? Bool ?? false))
            }
        } catch {
            return []
        }
    }

    /// Discover Kimi feature modes (from sidebar or inline).
    private static func discoverKimiFeatureModes(bridge: BrowserAutomationBridge) async -> [FeatureMode] {
        do {
            let rawModes = try await bridge.evaluateJS("""
                Array.from(document.querySelectorAll('[class*="sidebar"] a, [class*="nav"] a, [class*="sidebar"] button'))
                    .map(el => el.textContent.trim())
                    .filter(t => t.length > 0 && t.length < 40)
            """) as? [String] ?? []

            let featureNames = ["Slides", "Deep Research", "Swarm", "Kimi Work", "Kimi Code", "Слайды", "Глубокое исследование"]
            return rawModes.filter { name in
                featureNames.contains { name.contains($0) }
            }.map { FeatureMode(name: $0, icon: iconForMode($0), isEnabled: true) }
        } catch {
            return []
        }
    }

    /// Discover thinking/effort levels for Qwen.
    static func discoverThinkingLevels(using bridge: BrowserAutomationBridge) async -> [WebEffort] {
        do {
            try await bridge.click(selector: ".qwen-thinking-selector")
            try await bridge.waitForSelector(selector: ".ant-select-item-option", timeout: 5000)

            let rawLevels = try await bridge.evaluateJS("""
                Array.from(document.querySelectorAll('.ant-select-item-option-content'))
                    .map(el => el.textContent.trim())
            """) as? [String] ?? []

            return rawLevels.compactMap { WebEffort.fromLabel($0) }
        } catch {
            return []
        }
    }

    /// Map a mode name to an icon.
    private static func iconForMode(_ name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("image") || lower.contains("img") { return "photo" }
        if lower.contains("video") { return "video" }
        if lower.contains("research") || lower.contains("deep") { return "magnifyingglass" }
        if lower.contains("web") { return "globe" }
        if lower.contains("tool") { return "wrench" }
        if lower.contains("slides") || lower.contains("presentation") { return "rectangle.stack" }
        if lower.contains("code") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("swarm") { return "antenna.radiowaves.left.and.right" }
        return "sparkles"
    }
}
