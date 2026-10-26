import Foundation

// ProviderOption moved to ProviderOption.swift (Foundation-only, shared with
// LocalProviderConfig without pulling the whole serve-models chain).

enum ProviderSettingsLogic {
    static func providerID(for modelID: String, in providers: [MimoProviderResponse]) -> String? {
        for provider in providers {
            if provider.models[modelID] != nil {
                return provider.id
            }
        }
        return nil
    }

    static func model(
        for modelID: String,
        in providers: [MimoProviderResponse],
        providerID: String? = nil
    ) -> MimoProviderModel? {
        if let providerID,
           let provider = providers.first(where: { $0.id == providerID }) {
            return provider.models[modelID]
        }
        for provider in providers {
            if let model = provider.models[modelID] {
                return model
            }
        }
        return nil
    }

    static func models(
        for providerID: String,
        in providers: [MimoProviderResponse],
        customProviders: [CustomProvider]
    ) -> [String] {
        if let custom = customProviders.first(where: { $0.id == providerID && $0.isEnabled }) {
            return custom.models.sorted()
        }
        if let provider = providers.first(where: { $0.id == providerID }) {
            return provider.models.keys.sorted()
        }
        return []
    }

    static func defaultModel(
        for providerID: String,
        in providers: [MimoProviderResponse],
        customProviders: [CustomProvider]
    ) -> String? {
        let models = models(for: providerID, in: providers, customProviders: customProviders)
        return models.first
    }

    static func allProviderOptions(
        serverProviders: [MimoProviderResponse],
        customProviders: [CustomProvider],
        includeDisabled: Bool = false
    ) -> [ProviderOption] {
        var options = serverProviders.map {
            ProviderOption(id: $0.id, name: $0.name, isCustom: false, isConnected: true)
        }
        for custom in customProviders where includeDisabled || custom.isEnabled {
            options.append(ProviderOption(
                id: custom.id,
                name: custom.name,
                isCustom: true,
                isConnected: custom.isEnabled
            ))
        }
        return options
    }

    static func resolveProviderID(
        for modelID: String,
        selectedProviderID: String,
        in providers: [MimoProviderResponse],
        customProviders: [CustomProvider]
    ) -> String? {
        guard !modelID.isEmpty else { return nil }
        if !selectedProviderID.isEmpty {
            let scoped = models(for: selectedProviderID, in: providers, customProviders: customProviders)
            if scoped.contains(modelID) {
                return selectedProviderID
            }
        }
        if let serverID = providerID(for: modelID, in: providers) {
            return serverID
        }
        return customProviders.first(where: { $0.isEnabled && $0.models.contains(modelID) })?.id
    }

    static func isCustomProvider(
        _ providerID: String,
        customProviders: [CustomProvider]
    ) -> Bool {
        customProviders.contains { $0.id == providerID }
    }

    static func supportsReasoning(
        for modelID: String,
        in providers: [MimoProviderResponse],
        providerID: String? = nil,
        customProviders: [CustomProvider] = []
    ) -> Bool {
        if let providerID, isCustomProvider(providerID, customProviders: customProviders) {
            return false
        }
        return model(for: modelID, in: providers, providerID: providerID)?.capabilities?.reasoning == true
    }

    static func supportsToolcall(
        for modelID: String,
        providerID: String?,
        in providers: [MimoProviderResponse],
        customProviders: [CustomProvider]
    ) -> Bool {
        if let providerID, let custom = customProviders.first(where: { $0.id == providerID }) {
            return custom.supportsTools
        }
        guard let capabilities = model(for: modelID, in: providers, providerID: providerID)?.capabilities else {
            return true
        }
        return capabilities.toolcall != false
    }

    static func supportsPlanAgent(
        for modelID: String,
        providerID: String?,
        in providers: [MimoProviderResponse],
        customProviders: [CustomProvider]
    ) -> Bool {
        if let providerID, isCustomProvider(providerID, customProviders: customProviders) {
            return true
        }
        guard let capabilities = model(for: modelID, in: providers, providerID: providerID)?.capabilities else {
            return true
        }
        if capabilities.plan == true { return true }
        if capabilities.plan == false { return false }
        return capabilities.reasoning == true || capabilities.toolcall != false
    }

    static func availableVariants(
        for modelID: String,
        in providers: [MimoProviderResponse],
        providerID: String? = nil,
        customProviders: [CustomProvider] = []
    ) -> [String] {
        guard supportsReasoning(
            for: modelID,
            in: providers,
            providerID: providerID,
            customProviders: customProviders
        ),
              let variants = model(for: modelID, in: providers, providerID: providerID)?.variants else {
            return []
        }
        return variants.keys.sorted()
    }

    static func defaultVariant(
        for modelID: String,
        in providers: [MimoProviderResponse],
        providerID: String? = nil
    ) -> String? {
        let variants = availableVariants(for: modelID, in: providers, providerID: providerID)
        if variants.contains("high") { return "high" }
        return variants.last
    }

    static func normalizedVariant(
        _ variant: String?,
        for modelID: String,
        in providers: [MimoProviderResponse],
        providerID: String? = nil,
        customProviders: [CustomProvider] = []
    ) -> String? {
        let available = availableVariants(
            for: modelID,
            in: providers,
            providerID: providerID,
            customProviders: customProviders
        )
        guard !available.isEmpty else { return nil }
        if let variant, available.contains(variant) {
            return variant
        }
        return defaultVariant(for: modelID, in: providers, providerID: providerID)
    }

    static func mergeModelIDs(
        serverProviders: [MimoProviderResponse],
        customProviders: [CustomProvider],
        isDisabled: ((String, String) -> Bool)? = nil
    ) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for provider in serverProviders {
            for modelID in provider.models.keys.sorted() {
                if isDisabled?(provider.id, modelID) == true { continue }
                guard seen.insert(modelID).inserted else { continue }
                merged.append(modelID)
            }
        }
        for custom in customProviders where custom.isEnabled {
            for modelID in custom.models.sorted() {
                if isDisabled?(custom.id, modelID) == true { continue }
                guard seen.insert(modelID).inserted else { continue }
                merged.append(modelID)
            }
        }
        return merged
    }

    static func variantLabel(_ variant: String) -> String {
        variant.capitalized
    }

    static func migrateLegacyThinkingLevel(_ raw: String) -> String? {
        switch raw {
        case ThinkingLevel.noThinking.rawValue: return "low"
        case ThinkingLevel.high.rawValue: return "medium"
        case ThinkingLevel.max.rawValue: return "high"
        default: return raw.isEmpty ? nil : raw
        }
    }

    // Legacy helpers kept for tests during migration
    static func availableThinkingLevels(for modelID: String, in providers: [MimoProviderResponse]) -> [ThinkingLevel] {
        guard supportsReasoning(for: modelID, in: providers) else {
            return [.noThinking]
        }
        return ThinkingLevel.allCases
    }

    static func normalizedThinkingLevel(
        _ level: ThinkingLevel,
        for modelID: String,
        in providers: [MimoProviderResponse]
    ) -> ThinkingLevel {
        let available = availableThinkingLevels(for: modelID, in: providers)
        if available.contains(level) {
            return level
        }
        return available.first ?? .noThinking
    }
}
