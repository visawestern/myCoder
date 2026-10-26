import Foundation

/// Web-chat vendor supported for browser/cookie-based free-model access
/// (plan Раздел 12 Блок 1). Selectors/URLs live in `web_providers_catalog.json`
/// so a site redesign is fixed by data, not code.
enum WebChatVendor: String, Codable, CaseIterable, Identifiable {
    case kimi
    case qwen
    case chatgpt
    case claude
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kimi: return "Kimi"
        case .qwen: return "Qwen"
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        case .custom: return "Custom Web Chat"
        }
    }

    var defaultChatURL: String {
        switch self {
        case .kimi: return "https://www.kimi.ai/"
        case .qwen: return "https://chat.qwen.ai/"
        case .chatgpt: return "https://chatgpt.com/"
        case .claude: return "https://claude.ai/new"
        case .custom: return ""
        }
    }

    /// Models from catalog data (`web_providers_catalog.json`), never hardcoded
    /// in code. Empty when a vendor has no stable list (e.g. ChatGPT — models
    /// change frequently) until live discovery fills them in.
    var defaultModels: [String] {
        (try? WebProviderCatalog.loadBundled().models(for: id)) ?? []
    }
}

/// Effort/thinking level mapped to each vendor's toggle (plan Блок 1 п.6).
enum WebEffort: String, Codable, CaseIterable, Identifiable, Equatable {
    case low, medium, high
    var id: String { rawValue }

    /// Display name for UI.
    var displayName: String {
        switch self {
        case .low: return L.t(AppLocalizationKey.locEffortLow)
        case .medium: return L.t(AppLocalizationKey.locEffortMedium)
        case .high: return L.t(AppLocalizationKey.locEffortHigh)
        }
    }

    /// Map a label string to a WebEffort.
    static func fromLabel(_ label: String) -> WebEffort? {
        let lower = label.lowercased()
        if lower.contains("low") || lower.contains("fast") || lower.contains("quick") || lower.contains("низк") || lower.contains("быстр") || lower.contains("快") || lower.contains("快速") || lower.contains("低") { return .low }
        if lower.contains("medium") || lower.contains("standard") || lower.contains("balanced") || lower.contains("default") || lower.contains("средн") || lower.contains("авто") || lower.contains("自动") || lower.contains("auto") || lower.contains("标准") || lower.contains("中") { return .medium }
        if lower.contains("high") || lower.contains("deep") || lower.contains("reasoning") || lower.contains("thinking") || lower.contains("высок") || lower.contains("глубок") || lower.contains("мышлен") || lower.contains("深度") || lower.contains("推理") || lower.contains("高") || lower.contains("深思") { return .high }
        return nil
    }
}

/// How the browser session is driven (plan Блок 1 п.4).
enum WebTransport: String, Codable, CaseIterable, Identifiable {
    /// A dedicated managed browser under Playwright MCP control.
    case playwrightMCP
    /// Reuse the user's already-logged-in Chrome via CDP + its cookies.
    case cdpCookies
    var id: String { rawValue }
}

enum WebDiscoveryStatus: String, Codable, Equatable, Hashable {
    case active
    case inactive
    case unsupported
    case notDetected
    case error
}

/// Full configuration of a web-chat provider (plan Раздел 12 Блок 1 п.4).
/// A web provider model with its capabilities and available modes.
struct WebProviderModel: Codable, Equatable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    let description: String?
    var availableModes: [String]      // ["auto", "think", "fast", "image"]
    var availableEfforts: [WebEffort]
    var parameterProfile: WebModelParameterProfile
    var supportsImageGeneration: Bool
    var supportsDeepResearch: Bool
    var supportsWebDev: Bool
    var discoveryStatus: WebDiscoveryStatus
    var isLiveDiscovered: Bool
    var isSelectable: Bool
    var discoveryMessage: String?

    init(name: String, description: String? = nil, availableModes: [String] = [],
         availableEfforts: [WebEffort] = [],
         parameterProfile: WebModelParameterProfile = WebModelParameterProfile(),
         supportsImageGeneration: Bool = false, supportsDeepResearch: Bool = false,
         supportsWebDev: Bool = false,
         discoveryStatus: WebDiscoveryStatus = .notDetected,
         isLiveDiscovered: Bool = false,
         isSelectable: Bool = true,
         discoveryMessage: String? = nil) {
        self.name = name
        self.description = description
        self.availableModes = availableModes
        self.availableEfforts = availableEfforts
        self.parameterProfile = parameterProfile
        self.supportsImageGeneration = supportsImageGeneration
        self.supportsDeepResearch = supportsDeepResearch
        self.supportsWebDev = supportsWebDev
        self.discoveryStatus = discoveryStatus
        self.isLiveDiscovered = isLiveDiscovered
        self.isSelectable = isSelectable
        self.discoveryMessage = discoveryMessage
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, availableModes, availableEfforts, parameterProfile
        case supportsImageGeneration, supportsDeepResearch, supportsWebDev
        case discoveryStatus, isLiveDiscovered, isSelectable, discoveryMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        availableModes = try container.decodeIfPresent([String].self, forKey: .availableModes) ?? []
        availableEfforts = try container.decodeIfPresent([WebEffort].self, forKey: .availableEfforts) ?? []
        parameterProfile = try container.decodeIfPresent(WebModelParameterProfile.self, forKey: .parameterProfile) ?? WebModelParameterProfile()
        supportsImageGeneration = try container.decodeIfPresent(Bool.self, forKey: .supportsImageGeneration) ?? false
        supportsDeepResearch = try container.decodeIfPresent(Bool.self, forKey: .supportsDeepResearch) ?? false
        supportsWebDev = try container.decodeIfPresent(Bool.self, forKey: .supportsWebDev) ?? false
        discoveryStatus = try container.decodeIfPresent(WebDiscoveryStatus.self, forKey: .discoveryStatus) ?? .notDetected
        isLiveDiscovered = try container.decodeIfPresent(Bool.self, forKey: .isLiveDiscovered) ?? false
        isSelectable = try container.decodeIfPresent(Bool.self, forKey: .isSelectable) ?? true
        discoveryMessage = try container.decodeIfPresent(String.self, forKey: .discoveryMessage)
    }
}

/// A feature mode available for a web provider (e.g. Deep Research, Create Image).
struct FeatureMode: Codable, Equatable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let icon: String?
    let isEnabled: Bool

    init(name: String, icon: String? = nil, isEnabled: Bool = true) {
        self.name = name
        self.icon = icon
        self.isEnabled = isEnabled
    }
}

struct WebProviderConfig: Identifiable, Codable, Equatable {
    let id: String
    var vendor: WebChatVendor
    var displayName: String
    var transport: WebTransport
    var chatURL: String
    var cookieStorePath: String?
    var systemPrompt: String
    var selectedModel: String
    var effort: WebEffort
    /// Delay between browser actions (anti-captcha/anti-ban), milliseconds.
    var toolCallDelayMs: Int
    /// Keep-alive ping interval to prevent session drop, seconds.
    var sessionKeepAliveSec: Int
    var autoLogin: Bool
    var headless: Bool
    /// Max tool-loop iterations per user message (anti-runaway).
    var maxToolIterations: Int
    /// Legacy persisted field retained only for decoding older configurations.
    /// It is no longer shown or used as a runtime gate.
    var acknowledgedToS: Bool
    /// Real models parsed from the vendor's web UI model dropdown (plan Раздел
    /// 13 п.4). Empty until the driver discovers them; never hardcoded guesses.
    var discoveredModels: [WebProviderModel]
    /// Manually added model names (not auto-detected).
    var manuallyAddedModels: [String]
    /// Discovered effort/thinking levels from the vendor's web UI (plan Раздел 13 п.4).
    /// Empty until the driver discovers them.
    var discoveredEffortLevels: [WebEffort]
    /// Discovered feature modes (Deep Research, Create Image, etc).
    var discoveredFeatureModes: [FeatureMode]
    /// CSS/XPath selector for the effort/thinking/reasoning dropdown (plan Раздел 13 п.4).
    /// If present, the driver will use this to discover/change effort levels.
    var effortDropdown: String?
    /// User-picked CSS selector for the model dropdown (element picker).
    /// Overrides catalog selector when set.
    var customModelSelector: String?
    /// Active named login session. The actual cookies are stored separately by
    /// WebSessionManager under providerID/sessionID.
    var activeSessionID: String?
    var activeSessionName: String?

    init(id: String = UUID().uuidString,
         vendor: WebChatVendor,
         displayName: String? = nil,
         transport: WebTransport = .playwrightMCP,
         chatURL: String? = nil,
         cookieStorePath: String? = nil,
         systemPrompt: String = "",
         selectedModel: String? = nil,
         effort: WebEffort = .medium,
         toolCallDelayMs: Int = 800,
         sessionKeepAliveSec: Int = 120,
         autoLogin: Bool = false,
         headless: Bool = false,
         maxToolIterations: Int = 25,
         acknowledgedToS: Bool = false,
         discoveredModels: [WebProviderModel] = [],
         manuallyAddedModels: [String] = [],
         discoveredEffortLevels: [WebEffort] = [],
         discoveredFeatureModes: [FeatureMode] = [],
         effortDropdown: String? = nil,
         customModelSelector: String? = nil,
         activeSessionID: String? = nil,
         activeSessionName: String? = nil) {
        self.id = id
        self.vendor = vendor
        self.displayName = displayName ?? vendor.displayName
        self.transport = transport
        self.chatURL = chatURL ?? vendor.defaultChatURL
        self.cookieStorePath = cookieStorePath
        self.systemPrompt = systemPrompt
         self.selectedModel = selectedModel ?? ""
        self.effort = effort
        self.toolCallDelayMs = toolCallDelayMs
        self.sessionKeepAliveSec = sessionKeepAliveSec
        self.autoLogin = autoLogin
        self.headless = headless
        self.maxToolIterations = maxToolIterations
        self.acknowledgedToS = acknowledgedToS
        self.discoveredModels = discoveredModels
        self.manuallyAddedModels = manuallyAddedModels
        self.discoveredEffortLevels = discoveredEffortLevels
        self.discoveredFeatureModes = discoveredFeatureModes
        self.effortDropdown = effortDropdown
        self.customModelSelector = customModelSelector
        self.activeSessionID = activeSessionID
        self.activeSessionName = activeSessionName
    }

    /// A web provider's runtime readiness is determined by its captured session,
    /// live discovery and browser page state. The legacy ToS field is ignored.
    var isReady: Bool { true }

    /// The live effort capability of the selected model. An empty result means
    /// the provider exposed no thinking/effort control for that model.
    func efforts(for modelID: String) -> [WebEffort] {
        discoveredModels.first(where: { $0.name == modelID })?.availableEfforts ?? []
    }

    /// All models: auto-detected + explicitly configured. Vendor catalog data is
    /// intentionally not included because it goes stale independently of login.
    var allModels: [String] {
        var names = discoveredModels.filter(\.isSelectable).map { $0.name }
        names.append(contentsOf: manuallyAddedModels)
        return Array(Set(names)).sorted()
    }

    /// Add a custom model name to the provider's model list.
    /// No-op if the name is empty or already present (dedup by exact match).
    mutating func addCustomModel(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !allModels.contains(trimmed) else { return }
        manuallyAddedModels.append(trimmed)
    }

    /// Remove a custom model from the provider's model list.
    mutating func removeCustomModel(_ name: String) {
        manuallyAddedModels.removeAll { $0 == name }
    }
}

/// Persistence for web providers (plan Раздел 12 Блок 1 п.7).
enum WebProviderStore {
    static let storageKey = "com.mycoder.webProviders"

    /// Audit 2026-09-10: `load()` runs on EVERY SwiftUI body evaluation
    /// (send readiness, provider menus, status dot, API info) and each call
    /// redo JSON decode + per-model regex validation + a write-back check.
    /// With a ticking parent that is enough to saturate the main thread and
    /// starve MainActor API work. Cache the STANDARD-domain result briefly;
    /// explicit `defaults` suites (unit tests) always read through. `save()`
    /// invalidates, so writes are visible immediately.
    private static let cacheTTL: TimeInterval = 2
    private static let cacheLock = NSLock()
    private static var cachedStandard: (at: Date, value: [WebProviderConfig])?

    static func save(_ providers: [WebProviderConfig], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: storageKey)
        }
        if defaults == UserDefaults.standard {
            cacheLock.lock()
            cachedStandard = nil
            cacheLock.unlock()
        }
        NotificationCenter.default.post(name: .providersChanged, object: nil)
    }

    static func load(defaults: UserDefaults = .standard) -> [WebProviderConfig] {
        if defaults == UserDefaults.standard {
            cacheLock.lock()
            let hit = cachedStandard
            cacheLock.unlock()
            if let hit, Date().timeIntervalSince(hit.at) < cacheTTL {
                return hit.value
            }
        }
        guard let data = defaults.data(forKey: storageKey),
              let providers = try? JSONDecoder().decode([WebProviderConfig].self, from: data) else {
            return []
        }
        let sanitized = providers.map(sanitize)
        if let sanitizedData = try? JSONEncoder().encode(sanitized), sanitizedData != data {
            defaults.set(sanitizedData, forKey: storageKey)
        }
        if defaults == UserDefaults.standard {
            cacheLock.lock()
            cachedStandard = (at: Date(), value: sanitized)
            cacheLock.unlock()
        }
        return sanitized
    }

    /// Removes stale UI labels from catalogs persisted by older discovery
    /// versions. Only scraped `discoveredModels` go through the DOM-label
    /// validator; explicit `manuallyAddedModels` and the stored selection are
    /// user data and are preserved. An out-of-list selected model falls back
    /// to the first known model only when the list is non-empty.
    static func sanitize(_ config: WebProviderConfig) -> WebProviderConfig {
        var updated = config
        var seen = Set<String>()
        updated.discoveredModels = config.discoveredModels.compactMap { original in
            guard let normalized = WebModelListParser.normalize(original.name, vendor: config.vendor),
                  seen.insert(normalized.lowercased()).inserted else { return nil }
            var model = original
            model.name = normalized
            return model
        }
        // Manually added models are explicit user input, NOT scraped DOM text:
        // they must survive verbatim (trimmed, deduped). Running them through
        // the scraped-label validator drops legitimate names like
        // "another-model" that carry no version digit.
        var seenManual = Set<String>()
        updated.manuallyAddedModels = config.manuallyAddedModels.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 80,
                  seenManual.insert(trimmed).inserted else { return nil }
            return trimmed
        }
        updated.discoveredEffortLevels = Array(Set(updated.discoveredModels.flatMap(\.availableEfforts)))
            .sorted { $0.rawValue < $1.rawValue }
        if !updated.allModels.contains(updated.selectedModel) {
            // Fall back only when there is something to fall back to. With an
            // empty list there is no valid alternative, so the stored explicit
            // selection is preserved instead of being destroyed.
            if let first = updated.allModels.first {
                updated.selectedModel = first
            }
        }
        return updated
    }

    static func upsert(_ config: WebProviderConfig, in providers: [WebProviderConfig]) -> [WebProviderConfig] {
        var result = providers
        if let idx = result.firstIndex(where: { $0.id == config.id }) {
            result[idx] = config
        } else {
            result.append(config)
        }
        return result
    }
}
