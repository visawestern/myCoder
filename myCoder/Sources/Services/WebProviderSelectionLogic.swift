/// Canonical selection contract for browser-backed providers.
/// The composer and the WebChatDriver must consume the same persisted model and effort.
enum WebProviderSelectionLogic {
    static func selectedModel(for config: WebProviderConfig, availableModels: [String]? = nil) -> String {
        let models = availableModels ?? config.allModels
        guard !models.isEmpty else { return "" }
        if models.contains(config.selectedModel) {
            return config.selectedModel
        }
        return models.first ?? ""
    }

    /// Resolve the model that the composer and browser driver may safely use.
    /// A persisted model can disappear after live discovery; never propagate
    /// that stale identifier when a real discovered replacement exists.
    static func effectiveSelectedModel(for config: WebProviderConfig,
                                       availableModels: [String]? = nil) -> String {
        selectedModel(for: config, availableModels: availableModels)
    }

    static func modelForProviderSwitch(
        config: WebProviderConfig,
        globalSelectedModel: String,
        availableModels: [String]? = nil
    ) -> String {
        let models = availableModels ?? config.allModels
        if models.contains(config.selectedModel) {
            return config.selectedModel
        }
        if models.contains(globalSelectedModel) {
            return globalSelectedModel
        }
        return models.first ?? ""
    }

    static func selectingModel(_ modelID: String,
                               in config: WebProviderConfig,
                               availableModels: [String]? = nil) -> WebProviderConfig {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return config }
        let models = availableModels ?? config.allModels
        guard models.contains(modelID) else { return config }
        var updated = config
        updated.selectedModel = modelID
        return updated
    }

    static func availableEfforts(for config: WebProviderConfig,
                                 modelID: String? = nil) -> [WebEffort] {
        // A profiled live model owns its own capability list. Empty means the
        // selected model has no effort/thinking control and the composer must
        // hide the custom effort selector rather than exposing a global one.
        let resolvedModelID = modelID ?? config.selectedModel
        if let model = config.discoveredModels.first(where: { $0.name == resolvedModelID }) {
            return model.availableEfforts
        }
        // A concrete but undetected/manual/stale model has no verified
        // capability profile. Do not leak aggregate levels discovered for
        // another model into this model's composer.
        if !resolvedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        if !config.discoveredEffortLevels.isEmpty {
            return config.discoveredEffortLevels
        }
        // The exact effort control is vendor-page state, not a universal
        // capability. Do not expose synthetic levels before live discovery.
        return []
    }

    static func selectingEffort(_ effort: WebEffort,
                                in config: WebProviderConfig) -> WebProviderConfig {
        guard availableEfforts(for: config).contains(effort) else { return config }
        var updated = config
        updated.effort = effort
        return updated
    }
}
