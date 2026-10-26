/// Resolves a web provider's model while restoring persisted composer state.
/// Provider-local selection is authoritative; the global model is legacy fallback.
enum WebSelectionReconciliationLogic {
    static func modelForRestore(config: WebProviderConfig,
                                globalPreferredModel: String,
                                availableModels: [String]? = nil) -> String {
        let models = availableModels ?? config.allModels
        if models.contains(config.selectedModel) {
            return config.selectedModel
        }
        if models.contains(globalPreferredModel) {
            return globalPreferredModel
        }
        return models.first ?? ""
    }

    static func effortForModel(config: WebProviderConfig,
                               modelID: String,
                               availableEfforts: [WebEffort]) -> WebEffort? {
        guard !availableEfforts.isEmpty else { return nil }
        if availableEfforts.contains(config.effort),
           config.discoveredModels.contains(where: { $0.name == modelID }) {
            return config.effort
        }
        return availableEfforts.first
    }
}
