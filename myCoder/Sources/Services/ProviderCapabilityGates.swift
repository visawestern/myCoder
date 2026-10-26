import Foundation

enum ProviderCapabilityGates {
    static func canShowVariantMenu(
        modelID: String,
        providerID: String?,
        providers: [MimoProviderResponse],
        customProviders: [CustomProvider] = []
    ) -> Bool {
        !ProviderSettingsLogic.availableVariants(
            for: modelID,
            in: providers,
            providerID: providerID,
            customProviders: customProviders
        ).isEmpty
    }

    static func canSelectPlanAgent(
        modelID: String,
        providerID: String?,
        providers: [MimoProviderResponse],
        customProviders: [CustomProvider] = []
    ) -> Bool {
        ProviderSettingsLogic.supportsPlanAgent(
            for: modelID,
            providerID: providerID,
            in: providers,
            customProviders: customProviders
        )
    }

    static func canUseTools(
        modelID: String,
        providerID: String?,
        providers: [MimoProviderResponse],
        customProviders: [CustomProvider] = []
    ) -> Bool {
        ProviderSettingsLogic.supportsToolcall(
            for: modelID,
            providerID: providerID,
            in: providers,
            customProviders: customProviders
        )
    }

    static func planAgentDisabledReason(
        modelID: String,
        providerID: String?,
        providers: [MimoProviderResponse],
        customProviders: [CustomProvider] = []
    ) -> String? {
        canSelectPlanAgent(
            modelID: modelID,
            providerID: providerID,
            providers: providers,
            customProviders: customProviders
        ) ? nil : "This model does not support Plan mode."
    }

    static func variantMenuDisabledReason(
        modelID: String,
        providerID: String?,
        providers: [MimoProviderResponse],
        customProviders: [CustomProvider] = []
    ) -> String? {
        canShowVariantMenu(
            modelID: modelID,
            providerID: providerID,
            providers: providers,
            customProviders: customProviders
        ) ? nil : "Model doesn't support reasoning variants."
    }

    static func toolsUnavailableReason(
        modelID: String,
        providerID: String?,
        providers: [MimoProviderResponse],
        customProviders: [CustomProvider] = []
    ) -> String? {
        canUseTools(
            modelID: modelID,
            providerID: providerID,
            providers: providers,
            customProviders: customProviders
        ) ? nil : "Tools unavailable for this model or provider."
    }
}
