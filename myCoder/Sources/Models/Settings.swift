import Foundation

struct AppSettings: Codable {
    enum Theme: String, Codable {
        case dark, light
    }
    
    enum Zoom: String, Codable, CaseIterable {
        case smaller = "Smaller"
        case `default` = "Default"
        case larger = "Larger"
        
        var scale: CGFloat { fontScale }

        var fontScale: CGFloat {
            switch self {
            case .smaller: return 0.85
            case .default: return 1.0
            case .larger: return 1.15
            }
        }
    }
    
    var theme: Theme
    var language: String
    var zoom: Zoom
    var showLineNumbers: Bool
    var wrapLongLines: Bool
    var codeFontSize: Int
    var inheritTerminalProfile: Bool
    var terminalFont: String
    var httpProxy: String
    var lightCodeTheme: String
    var darkCodeTheme: String
    var indexNewFolders: Bool
    var indexRepositories: Bool
    
    private static let userDefaultsKey = "com.mycoder.settings"
    
    init() {
        self.theme = .dark
        self.language = "English"
        self.zoom = .default
        self.showLineNumbers = true
        self.wrapLongLines = true
        self.codeFontSize = 12
        self.inheritTerminalProfile = true
        self.terminalFont = ""
        self.httpProxy = ""
        self.lightCodeTheme = "GitHub Light"
        self.darkCodeTheme = "GitHub Dark"
        self.indexNewFolders = true
        self.indexRepositories = true
    }
    
    static func load() -> AppSettings {
        load(from: .standard)
    }

    /// Load from an injected defaults domain (tests use a dedicated suite so
    /// parallel test runs never race on the shared `.standard` domain).
    static func load(from defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }
    
    func save() {
        save(to: .standard)
    }

    /// Save to an injected defaults domain (see load(from:)).
    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.userDefaultsKey)
        }
    }
}

struct CustomProvider: Identifiable, Codable {
    let id: String
    var name: String
    var type: ProviderType
    var baseURL: String
    var apiKey: String
    var isEnabled: Bool
    var models: [String]
    var supportsTools: Bool
    var acpEnabled: Bool
    var requiresAPIKey: Bool
    /// Model ids added by hand (added, cloned, or rename targets). They
    /// survive a catalog refresh: the fetched list is merged with these.
    var customModels: [String]
    /// Discovered ids the user removed or renamed away; a refresh must not
    /// resurrect them.
    var hiddenModels: [String]

    init(
        id: String = UUID().uuidString,
        name: String,
        type: ProviderType,
        baseURL: String,
        apiKey: String = "",
        isEnabled: Bool = true,
        models: [String] = [],
        supportsTools: Bool = true,
        acpEnabled: Bool = false,
        requiresAPIKey: Bool = true,
        customModels: [String] = [],
        hiddenModels: [String] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.isEnabled = isEnabled
        self.models = models
        self.supportsTools = supportsTools
        self.acpEnabled = acpEnabled
        self.requiresAPIKey = requiresAPIKey
        self.customModels = customModels
        self.hiddenModels = hiddenModels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(ProviderType.self, forKey: .type)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? []
        supportsTools = try container.decodeIfPresent(Bool.self, forKey: .supportsTools) ?? true
        acpEnabled = try container.decodeIfPresent(Bool.self, forKey: .acpEnabled) ?? false
        requiresAPIKey = try container.decodeIfPresent(Bool.self, forKey: .requiresAPIKey) ?? true
        customModels = try container.decodeIfPresent([String].self, forKey: .customModels) ?? []
        hiddenModels = try container.decodeIfPresent([String].self, forKey: .hiddenModels) ?? []
    }
}

/// Merge rule for a custom provider's model list: the catalog fetched from
/// the server and the user's manual entries (customModels) are unioned, then
/// everything the user removed or renamed away (hiddenModels) is dropped.
/// Renames therefore survive a refresh instead of being reverted by it.
enum CustomModelListLogic {
    static func mergedModels(provider: CustomProvider, discovered: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in discovered + provider.customModels {
            guard !entry.isEmpty, !seen.contains(entry), !provider.hiddenModels.contains(entry) else { continue }
            seen.insert(entry)
            result.append(entry)
        }
        return result.sorted()
    }
}

enum ProviderType: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI Compatible"
    case openRouter = "OpenRouter"
    case openModel = "OpenModel"
    case openCodeZen = "OpenCode Zen"
    case ollama = "Ollama"
    case anthropic = "Anthropic"
    case google = "Google AI"
    case mistral = "Mistral"
    case groq = "Groq"
    case deepseek = "DeepSeek"
    case omni = "OmniRouter"
    case nvidia = "NVIDIA"
    case acp = "ACP (Agent Coder Protocol)"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .openAI: return "cpu"
        case .openRouter: return "arrow.triangle.branch"
        case .openModel: return "globe.americas.fill"
        case .openCodeZen: return "sparkles"
        case .ollama: return "desktopcomputer"
        case .anthropic: return "brain.head.profile"
        case .google: return "globe"
        case .mistral: return "wind"
        case .groq: return "bolt.fill"
        case .deepseek: return "waveform.path.ecg"
        case .omni: return "arrow.triangle.merge"
        case .nvidia: return "memorychip"
        case .acp: return "terminal.fill"
        }
    }
    
    var defaultURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .openModel: return "https://api.openmodel.ai/v1"
        case .openCodeZen: return OpenCodeZenCatalog.baseURL
        case .ollama: return "http://localhost:11434/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .omni: return "https://api.omnirouter.app/v1"
        case .nvidia: return "https://integrate.api.nvidia.com/v1"
        case .acp: return "http://localhost:8080/acp/v1"
        }
    }
    
    /// API endpoint type - determines how requests are formatted
    var endpointType: EndpointType {
        switch self {
        case .openRouter:
            return .openRouter
        case .omni:
            return .omniRouter
        case .acp:
            return .agentCodeProtocol
        default:
            return .openAI
        }
    }
    
    /// Human-readable description of how this provider's API works
    var endpointDescription: String {
        switch endpointType {
        case .openAI:
            return "OpenAI-compatible API (chat/completions endpoint)"
        case .openRouter:
            return "OpenRouter API with model routing and fallbacks"
        case .omniRouter:
            return "OmniRouter API with fine-grained model selection"
        case .agentCodeProtocol:
            return "ACP (Agent Coder Protocol) for autonomous coding tasks"
        }
    }
}

/// API endpoint type for different provider behaviors
enum EndpointType: String, Codable, CaseIterable {
    case openAI = "openai"
    case openRouter = "openrouter"
    case omniRouter = "omni"
    case agentCodeProtocol = "acp"
}

enum AccessLevel: String, CaseIterable, Identifiable {
    case askBeforeChanges = "Ask before changes"
    case editAutomatically = "Edit automatically"
    case fullAccess = "Full access"

    var id: String { rawValue }

    /// Localized display name (used in UI menus).
    var displayName: String {
        switch self {
        case .askBeforeChanges: return L.t(AppLocalizationKey.locAccessAskBefore)
        case .editAutomatically: return L.t(AppLocalizationKey.locAccessEditAuto)
        case .fullAccess: return L.t(AppLocalizationKey.locAccessFull)
        }
    }

    /// Localized short description shown under the name.
    var displayDescription: String {
        switch self {
        case .askBeforeChanges: return L.t(AppLocalizationKey.locAccessAskBeforeDesc)
        case .editAutomatically: return L.t(AppLocalizationKey.locAccessEditAutoDesc)
        case .fullAccess: return L.t(AppLocalizationKey.locAccessFullDesc)
        }
    }

    // Legacy descriptions (kept for migration / non-localized contexts)
    var description: String {
        switch self {
        case .askBeforeChanges: return "Ask before file changes."
        case .editAutomatically: return "Edit files automatically."
        case .fullAccess: return "Run with fewer confirmations."
        }
    }
    
    var icon: String {
        switch self {
        case .askBeforeChanges: return "hand.raised"
        case .editAutomatically: return "pencil"
        case .fullAccess: return "bolt.fill"
        }
    }
}

enum ThinkingLevel: String, CaseIterable, Identifiable {
    case noThinking = "No thinking"
    case high = "High"
    case max = "Max"
    
    var id: String { rawValue }
}

enum AgentMode: String, CaseIterable, Identifiable {
    case build = "Build"
    case plan = "Plan"
    case compose = "Compose"

    var displayName: String {
        switch self {
        case .build: return L.t(AppLocalizationKey.locModeBuild)
        case .plan: return L.t(AppLocalizationKey.locModePlan)
        case .compose: return L.t(AppLocalizationKey.locModeCompose)
        }
    }
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .build: return "hammer.fill"
        case .plan: return "text.book.closed"
        case .compose: return "square.and.pencil"
        }
    }
}
