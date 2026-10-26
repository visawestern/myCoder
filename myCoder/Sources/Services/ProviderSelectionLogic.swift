import Foundation

struct ProviderSelectionResult: Equatable {
    let providerID: String
    let modelID: String
    let variant: String?
}

enum ProviderSelectionLogic {
    /// Recomputes model and variant when the user switches provider. Does not change access level or agent mode.
    static func cascade(
        to providerID: String,
        currentModelID: String,
        currentVariant: String?,
        serverProviders: [MimoProviderResponse],
        customProviders: [CustomProvider]
    ) -> ProviderSelectionResult {
        let models = ProviderSettingsLogic.models(
            for: providerID,
            in: serverProviders,
            customProviders: customProviders
        )

        let modelID: String
        if models.contains(currentModelID) {
            modelID = currentModelID
        } else if let defaultModel = ProviderSettingsLogic.defaultModel(
            for: providerID,
            in: serverProviders,
            customProviders: customProviders
        ) {
            modelID = defaultModel
        } else {
            modelID = models.first ?? ""
        }

        let variant = ProviderSettingsLogic.normalizedVariant(
            currentVariant,
            for: modelID,
            in: serverProviders,
            providerID: providerID,
            customProviders: customProviders
        )

        return ProviderSelectionResult(
            providerID: providerID,
            modelID: modelID,
            variant: variant
        )
    }
}
