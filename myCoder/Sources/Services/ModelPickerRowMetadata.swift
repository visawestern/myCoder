import Foundation

/// Everything a model row in the composer dropdown needs, computed once per
/// dropdown open instead of once per row per render.
struct ModelPickerRowMetadata: Equatable {
    var isSelected = false
    var badges: [ModelCapabilityBadge] = []
    var context: Int? = nil
    var isInternal = false
    var canBeInternal = false
}

enum ModelPickerRowMetadataBuilder {

    /// Builds row metadata for every model of the selected provider.
    ///
    /// `canBeInternalForProvider` does not depend on the model id, so it is
    /// passed in precomputed — the old per-row path re-ran
    /// `InternalModelResolver.route`, which for custom providers (e.g.
    /// OpenRouter) hit the Keychain once per model. Thousands of Keychain
    /// lookups on the main thread froze the dropdown for large catalogs
    /// (user report 2026-11-12).
    static func build(
        modelIDs: [String],
        providerID: String,
        selectedModel: String,
        effectiveModel: String,
        serverProviders: [MimoProviderResponse],
        isInternal: (String) -> Bool,
        canBeInternalForProvider: Bool
    ) -> [String: ModelPickerRowMetadata] {
        let providerParam: String? = providerID.isEmpty ? nil : providerID
        var metadata: [String: ModelPickerRowMetadata] = [:]
        metadata.reserveCapacity(modelIDs.count)
        for modelID in modelIDs {
            metadata[modelID] = ModelPickerRowMetadata(
                isSelected: ModelSelectionPresentationLogic.isSelected(
                    candidate: modelID,
                    selectedModel: selectedModel,
                    effectiveModel: effectiveModel
                ),
                badges: ModelCapabilityLogic.badges(
                    for: modelID,
                    in: serverProviders,
                    providerID: providerParam
                ),
                context: ModelCapabilityLogic.contextWindow(
                    for: modelID,
                    in: serverProviders,
                    providerID: providerParam
                ),
                isInternal: isInternal(modelID),
                canBeInternal: canBeInternalForProvider
            )
        }
        return metadata
    }

    /// Whether ANY model of the selected provider can be marked internal.
    ///
    /// This mirrors the semantics of `InternalModelResolver.route` for a
    /// representative model id, but never touches credential storage: the
    /// result depends only on provider config presence/enablement, so there is
    /// no Keychain/UserDefaults read on dropdown open.
    static func canBeInternalForProvider(
        providerID: String,
        modelIDs: [String],
        customProviders: [CustomProvider],
        localProviders: [LocalProviderConfig],
        serverProviders: [MimoProviderResponse]
    ) -> Bool {
        guard !providerID.isEmpty, !modelIDs.isEmpty else { return false }
        if customProviders.contains(where: { $0.id == providerID && $0.isEnabled }) {
            return true
        }
        if localProviders.contains(where: { $0.id == providerID && $0.isEnabled }) {
            return true
        }
        let servers = serverProviders.isEmpty ? ServerProviderCatalogStore.load() : serverProviders
        return servers.contains(where: { $0.id == providerID })
    }
}
