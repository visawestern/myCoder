import Foundation

/// Per-model call parameters editable from the model menu popover
/// (plan Раздел 13 п.14). Persisted per model id so each model remembers its
/// own settings. Values are optional so "unset" means "use provider default".
struct ModelCallParameters: Codable, Equatable, Hashable {
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
    var systemPrompt: String?

    init(temperature: Double? = nil, maxTokens: Int? = nil, topP: Double? = nil, systemPrompt: String? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.systemPrompt = systemPrompt
    }

    /// Whether any parameter is customized (for a badge/indicator).
    var isCustomized: Bool {
        temperature != nil
            || maxTokens != nil
            || topP != nil
            || !(systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

/// Runtime parameter surface discovered from a vendor's live model UI.
/// `values` is a safe snapshot; user overrides remain in ModelCallParametersStore.
struct WebModelParameterProfile: Codable, Equatable, Hashable {
    var availableKeys: [String]
    var labels: [String]
    var values: ModelCallParameters

    init(availableKeys: [String] = [], labels: [String] = [], values: ModelCallParameters = ModelCallParameters()) {
        self.availableKeys = availableKeys
        self.labels = labels
        self.values = values
    }

    var isEmpty: Bool { availableKeys.isEmpty && labels.isEmpty && !values.isCustomized }
}

/// Pure persistence + serialization of per-model parameters (plan Раздел 13 п.14).
enum ModelCallParametersStore {
    static let storageKey = "com.mycoder.modelCallParameters"

    static func loadAll(defaults: UserDefaults = .standard) -> [String: ModelCallParameters] {
        guard let data = defaults.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: ModelCallParameters].self, from: data) else {
            return [:]
        }
        return map
    }

    static func saveAll(_ map: [String: ModelCallParameters], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func parameters(for modelID: String, defaults: UserDefaults = .standard) -> ModelCallParameters {
        normalized(loadAll(defaults: defaults)[modelID] ?? ModelCallParameters())
    }

    static func set(_ params: ModelCallParameters, for modelID: String, defaults: UserDefaults = .standard) {
        var map = loadAll(defaults: defaults)
        let value = normalized(params)
        if value.isCustomized {
            map[modelID] = value
        } else {
            map.removeValue(forKey: modelID)
        }
        saveAll(map, defaults: defaults)
    }

    /// Build the request body fragment for a provider call (only set keys).
    static func requestFragment(_ params: ModelCallParameters) -> [String: Any] {
        var body: [String: Any] = [:]
        if let t = params.temperature { body["temperature"] = t }
        if let m = params.maxTokens { body["max_tokens"] = m }
        if let p = params.topP { body["top_p"] = p }
        if let s = params.systemPrompt {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { body["system"] = trimmed }
        }
        return body
    }

    private static func normalized(_ params: ModelCallParameters) -> ModelCallParameters {
        var value = params
        if let prompt = value.systemPrompt {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            value.systemPrompt = trimmed.isEmpty ? nil : trimmed
        }
        return value
    }
}
