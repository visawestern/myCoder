import Foundation

/// Local provider kinds configurable in the unified Providers tab.
///
/// The app is fully decoupled from any local CLI: it NEVER spawns `ollama`,
/// `opencode`, or `mimo`, and it never launches a serve process. A local
/// provider is only ever reached over HTTP at a `host:port` the **user** has
/// already started themselves (e.g. `ollama serve`, an OpenCode server, or a
/// local agent on localhost). No executable paths, no auto-start, no CLI mode.
enum LocalProviderKind: String, Codable, CaseIterable, Identifiable {
    case ollama
    case openCode
    /// STRATA local inference server (OpenAI-compatible /v1 API, port 8399).
    case strata

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .openCode: return "OpenCode"
        case .strata: return "STRATA"
        }
    }

    var icon: String {
        switch self {
        case .ollama: return "desktopcomputer"
        case .openCode: return "terminal"
        case .strata: return "square.stack.3d.up"
        }
    }

    /// Health-check endpoint path used to verify the local HTTP server is up.
    var healthPath: String {
        switch self {
        case .ollama: return "/api/tags"
        case .openCode: return "/global/health"
        case .strata: return "/v1/models"
        }
    }

    var defaultPort: Int {
        switch self {
        case .ollama: return 11434
        case .openCode: return 4096
        case .strata: return 8399
        }
    }
}

/// Configuration of a local provider reached over HTTP. There is exactly one
/// way to reach it — connect to a server the user is already running on
/// `host:port`. No CLI mode, no executable path, no auto-start.
///
/// `opencode serve` requires HTTP basic auth on every endpoint (verified live:
/// without `OPENCODE_SERVER_PASSWORD` everything is 401), so OpenCode-kind
/// configs carry a username + a Keychain-stored password. The password is
/// deliberately excluded from Codable — it never lands in UserDefaults JSON.
struct LocalProviderConfig: Identifiable, Codable, Equatable {
    let id: String
    var kind: LocalProviderKind
    /// Optional user-visible name. Empty/nil falls back to the kind name.
    var name: String?
    var host: String
    var port: Int
    var isEnabled: Bool
    var models: [String]
    /// Basic-auth username for servers that require it (opencode serve).
    /// Empty = no auth header is sent.
    var username: String
    /// Provider id sent to an OpenCode server when creating a message.
    /// `opencode serve` hosts several providers; the app default is the
    /// built-in `opencode` provider, but a local server may expose an
    /// OpenAI-compatible provider such as `ollama` under its own id.
    var openCodeProviderID: String

    enum CodingKeys: String, CodingKey {
        case id, kind, name, host, port, isEnabled, models, username, openCodeProviderID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(LocalProviderKind.self, forKey: .kind)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        models = try c.decode([String].self, forKey: .models)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        openCodeProviderID = try c.decodeIfPresent(String.self, forKey: .openCodeProviderID) ?? "opencode"
    }

    init(id: String = UUID().uuidString,
         kind: LocalProviderKind,
         name: String? = nil,
         host: String = "127.0.0.1",
         port: Int? = nil,
         isEnabled: Bool = true,
         models: [String] = [],
         username: String = "",
         openCodeProviderID: String = "opencode") {
        self.id = id
        self.kind = kind
        self.name = name
        self.host = host
        self.port = port ?? kind.defaultPort
        self.isEnabled = isEnabled
        self.models = models
        self.username = username
        self.openCodeProviderID = openCodeProviderID
    }

    /// Base URL for the serve endpoint (used for health-check and model list).
    var serveBaseURL: String { "http://\(host):\(port)" }

    /// Endpoint the client actually talks to. Every supported local kind
    /// serves its API from the plain origin.
    var apiBaseURL: String { serveBaseURL }

    var healthURL: String { apiBaseURL + kind.healthPath }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? kind.displayName : trimmed
    }

    /// Keychain identifier for this provider's basic-auth password.
    var passwordKeychainIdentifier: String { "local-provider-password-\(id)" }

    /// Pure Basic-auth header value, or nil when no password is set.
    /// The password travels as a parameter (never read here) so the helper
    /// stays testable without touching the Keychain.
    static func basicAuthHeader(username: String, password: String) -> String? {
        guard !password.isEmpty else { return nil }
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else { return nil }
        return "Basic " + data.base64EncodedString()
    }

    /// HTTP headers for authenticated requests to this provider's server.
    /// Password comes from the Keychain; missing/empty password = no header.
    func authHeaders() -> [String: String] {
        guard !username.isEmpty,
              let password = try? KeychainManager.shared.getSecret(identifier: passwordKeychainIdentifier),
              let header = Self.basicAuthHeader(username: username, password: password) else {
            return [:]
        }
        return ["Authorization": header]
    }

    /// Store the basic-auth password in the Keychain (never in UserDefaults).
    func savePassword(_ password: String) throws {
        if password.isEmpty {
            try? KeychainManager.shared.deleteSecret(identifier: passwordKeychainIdentifier)
            return
        }
        try KeychainManager.shared.saveSecret(password, identifier: passwordKeychainIdentifier)
    }
}

/// Pure logic for the unified Providers tab (plan Раздел 1 Блок 3-5).
enum LocalProviderLogic {
    static let storageKey = "com.mycoder.localProviders"

    /// Persist local providers to UserDefaults (plan Блок 4 п.38).
    static func save(_ providers: [LocalProviderConfig], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: storageKey)
        }
        NotificationCenter.default.post(name: .providersChanged, object: nil)
    }

    static func load(defaults: UserDefaults = .standard) -> [LocalProviderConfig] {
        guard let data = defaults.data(forKey: storageKey),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }
        // Decode one entry at a time so a legacy provider kind that no longer
        // exists (localAgent / acp / openAICompatible) is dropped without
        // wiping every other configured local provider.
        let decoder = JSONDecoder()
        var providers: [LocalProviderConfig] = []
        var droppedEntry = false
        for item in raw {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item),
                  let provider = try? decoder.decode(LocalProviderConfig.self, from: itemData) else {
                droppedEntry = true
                continue
            }
            providers.append(provider)
        }
        if droppedEntry, let cleaned = try? JSONEncoder().encode(providers) {
            defaults.set(cleaned, forKey: storageKey)
        }
        return providers
    }

    /// Persist an edited local provider (host, port, credentials, models).
    static func update(_ config: LocalProviderConfig, defaults: UserDefaults = .standard) {
        var providers = load(defaults: defaults)
        if let index = providers.firstIndex(where: { $0.id == config.id }) {
            providers[index] = config
        } else {
            providers.append(config)
        }
        save(providers, defaults: defaults)
    }

    /// Delete a local provider and return the remaining list.
    @discardableResult
    static func remove(id: String, defaults: UserDefaults = .standard) -> [LocalProviderConfig] {
        var providers = load(defaults: defaults)
        providers.removeAll { $0.id == id }
        save(providers, defaults: defaults)
        return providers
    }

    /// Disable or re-enable a local provider without deleting it.
    static func setEnabled(id: String, isEnabled: Bool, defaults: UserDefaults = .standard) {
        var providers = load(defaults: defaults)
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[index].isEnabled = isEnabled
        save(providers, defaults: defaults)
    }

    /// Current switch state of one local provider, read from the config so a
    /// card never shows the value it was created with.
    static func isEnabled(id: String, defaults: UserDefaults = .standard) -> Bool {
        load(defaults: defaults).first(where: { $0.id == id })?.isEnabled ?? false
    }

    /// Remove one model from a local provider's stored catalog.
    static func removeModel(_ modelID: String, from providerID: String, defaults: UserDefaults = .standard) {
        var providers = load(defaults: defaults)
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        providers[index].models.removeAll { $0 == modelID }
        save(providers, defaults: defaults)
    }

    /// Merge local providers into the unified provider option list alongside
    /// server + custom providers (plan Блок 4 п.39).
    static func providerOptions(
        from locals: [LocalProviderConfig],
        includeDisabled: Bool = false
    ) -> [ProviderOption] {
        locals.filter { includeDisabled || $0.isEnabled }.map {
            ProviderOption(id: $0.id, name: $0.displayName, isCustom: true, isConnected: $0.isEnabled)
        }
    }

    /// Fetch live models from a local provider's HTTP endpoint. Returns nil on
    /// any failure so callers can keep the existing list rather than wiping it.
    /// Authenticated when the config carries basic-auth credentials (opencode
    /// serve locks every endpoint without them).
    static func fetchModels(for config: LocalProviderConfig) async -> [String]? {
        let endpoint: String
        switch config.kind {
        case .ollama:
            endpoint = config.serveBaseURL + "/api/tags"
        case .openCode:
            endpoint = config.serveBaseURL + "/config/providers"
        case .strata:
            endpoint = config.serveBaseURL + "/v1/models"
        }
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        for (field, value) in config.authHeaders() {
            request.setValue(value, forHTTPHeaderField: field)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            if config.kind == .openCode {
                return ProviderAutoDetector.parseOpenCodeProviders(data, providerID: config.openCodeProviderID)
            }
            return parseModels(from: data, kind: config.kind)
        } catch {
            return nil
        }
    }

    /// Parse model list from each vendor's JSON shape.
    private static func parseModels(from data: Data, kind: LocalProviderKind) -> [String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var names: [String] = []
        switch kind {
        case .ollama:
            if let dict = json as? [String: Any], let models = dict["models"] as? [[String: Any]] {
                names = models.compactMap { $0["name"] as? String }
            }
        case .openCode:
            if let dict = json as? [String: Any], let models = dict["models"] as? [[String: Any]] {
                names = models.compactMap { $0["id"] as? String ?? $0["name"] as? String }
            } else if let models = json as? [[String: Any]] {
                names = models.compactMap { $0["id"] as? String ?? $0["name"] as? String }
            }
        case .strata:
            return ProviderAutoDetector.parseOpenAIModels(data)
        }
        return names.isEmpty ? nil : names
    }
}

/// Confirmation step for auto-detection (E23 — Раздел 9 п.30): the detector
/// must never add a provider on its own; it presents the finding and the user
/// explicitly confirms ("Подтвердить и добавить") or cancels. This logic builds
/// the confirmation copy and the config that confirmation would add, keeping
/// the no-auto-add rule testable and out of the view.
enum LocalProviderConfirmLogic {

    /// Short title naming the detected provider kind.
    static func title(for info: DetectedProviderInfo) -> String {
        "Detected: \(displayName(for: info.kind))"
    }

    /// Full confirmation copy: endpoint + model count.
    static func message(for info: DetectedProviderInfo, host: String, port: Int) -> String {
        "Found a \(displayName(for: info.kind)) provider at \(host):\(port) with \(info.models.count) model(s). Add it?"
    }

    /// The config that confirming would add — maps the detected kind to the
    /// unified local-provider card set. ACP stays ACP (never folded into
    /// OpenCode, which would route to an endpoint the ACP server doesn't speak).
    static func config(from info: DetectedProviderInfo, host: String, port: Int) -> LocalProviderConfig {
        let kind: LocalProviderKind
        switch info.kind {
        case .ollama: kind = .ollama
        case .openCode: kind = .openCode
        case .strata: kind = .strata
        }
        return LocalProviderConfig(kind: kind, host: host, port: port, models: info.models)
    }

    /// Pure credential attach for the confirm step: username persists on the
    /// config; the password is returned for the caller to store in the
    /// Keychain (never in UserDefaults — see OC-1 test).
    /// Returns the updated config (password is NOT embedded in it).
    static func applyCredentials(to config: LocalProviderConfig, username: String) -> LocalProviderConfig {
        var updated = config
        updated.username = username
        return updated
    }

    /// True when a config for the same host:port is already configured —
    /// confirming a duplicate would add nothing (E23 dedupe, kept testable and
    /// out of the view).
    static func isDuplicate(_ locals: [LocalProviderConfig], of cfg: LocalProviderConfig) -> Bool {
        locals.contains { $0.host == cfg.host && $0.port == cfg.port }
    }

    static func displayName(for kind: DetectedProviderInfo.Kind) -> String {
        switch kind {
        case .ollama: return "Ollama"
        case .openCode: return "OpenCode"
        case .strata: return "STRATA"
        }
    }
}

/// User-facing status lines for the auto-detect flow (E23). Detection must
/// never add a provider on its own, and the status line must not claim a
/// provider was added when it was only detected, cancelled, or confirmed —
/// the old single "Detected: …" line was still shown after a cancel.
enum AutoDetectStatusText {
    /// Heuristic warning for non-local addresses (plan Блок 3 п.34). Returns
    /// nil for local addresses so the caller can compose it ahead of the result.
    static func warningForNonLocal(_ host: String) -> String? {
        ProviderAutoDetector.isLikelyLocal(host) ? nil : "Warning: \(host) is not a local address."
    }

    /// Shown right after detection, BEFORE the user confirms.
    static func detected(_ info: DetectedProviderInfo, host: String, port: Int) -> String {
        "Detected: \(LocalProviderConfirmLogic.displayName(for: info.kind)), \(info.models.count) model(s). Confirm to add."
    }

    static func nothingDetected(host: String, port: Int) -> String {
        "Nothing detected at \(host):\(port). Add manually below."
    }

    static func confirmed(_ info: DetectedProviderInfo, host: String, port: Int) -> String {
        "Added: \(LocalProviderConfirmLogic.displayName(for: info.kind)) at \(host):\(port)."
    }

    static func cancelled() -> String {
        "Detection cancelled — nothing was added."
    }

    static func invalidAddress() -> String {
        "Enter an address as host:port."
    }
}

/// Pure reconcile for background model-list refreshes of local providers.
/// Refresh must never leave the user model-less: a failed/empty refresh
/// keeps the current selection, and an empty selection takes the first
/// fresh model. No I/O here — fetching + persistence stay in the caller.
enum LocalModelRefreshLogic {
    static func reconcile(current: String, fresh: [String]) -> String {
        if fresh.isEmpty { return current }
        if current.isEmpty { return fresh[0] }
        return fresh.contains(current) ? current : fresh[0]
    }
}
