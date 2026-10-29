import Foundation

/// One selectable model in the spec wizard, together with everything the
/// picker can honestly say about it. The wizard needs the provider id because
/// a model id is not unique across providers (`gpt-4o` can exist in several
/// catalogs) and because routing must not depend on the app-wide selection.
struct SpecModelOption: Identifiable, Equatable {
    let providerID: String
    let providerName: String
    let modelID: String
    let metadata: SpecModelMetadata

    var id: String { providerID + "\u{1F}" + modelID }
    var displayName: String { metadata.displayName }
}

/// Metadata shown in the hover card. Optional capability fields are
/// deliberately tri-state: `nil` means "not reported", never "no".
struct SpecModelMetadata: Equatable {
    enum Source: String, Equatable {
        case autoFree
        case custom
        case local

        var icon: String {
            switch self {
            case .autoFree: return "sparkles"
            case .custom: return "cloud"
            case .local: return "desktopcomputer"
            }
        }

        var label: String {
            switch self {
            case .autoFree: return "Free"
            case .custom: return "Cloud"
            case .local: return "Local"
            }
        }
    }

    var source: Source
    var displayName: String
    /// Context window reported by the provider or the bundled catalog.
    var contextWindow: Int?
    /// Concrete window used by the app (reported value or catalog default).
    var effectiveContextWindow: Int
    var outputLimit: Int?
    var effectiveOutputLimit: Int
    var reasoning: Bool?
    var toolCall: Bool?
    var plan: Bool?
    var vision: Bool?
    var imageGeneration: Bool?
    /// Cost per 1M tokens, when the catalog reports it.
    var costInput: Double?
    var costOutput: Double?
    var description: String?
    var isFree: Bool

    var isContextReported: Bool { contextWindow != nil }
}

/// A provider node in the wizard's model tree. Only providers the wizard can
/// address directly are included: a chat session or a browser transport would
/// create visible side effects the wizard must not have.
struct SpecModelGroup: Identifiable, Equatable {
    let providerID: String
    let providerName: String
    let source: SpecModelMetadata.Source
    let models: [SpecModelOption]

    var id: String { providerID }
}

/// Builds the provider → model tree for the wizard's planning/coding pickers.
/// Pure logic: every value comes from configured providers, the bundled
/// metadata catalog, user overrides, or the live Auto Free catalog — nothing
/// is invented. Disabled providers and disabled models never appear.
enum SpecWizardModelCatalog {
    static func groups(
        serverProviders: [MimoProviderResponse],
        customProviders: [CustomProvider],
        localProviders: [LocalProviderConfig],
        autoFree: MyCoderAutoFreeProvider,
        defaults: UserDefaults = .standard
    ) -> [SpecModelGroup] {
        let overrides = ModelMetadataStore.loadAll(defaults: defaults)
        var groups: [SpecModelGroup] = []

        if autoFree.isEnabled {
            let group = autoFreeGroup(
                provider: autoFree,
                defaults: defaults
            )
            if !group.models.isEmpty { groups.append(group) }
        }

        let customGroups = customProviders
            .filter { $0.isEnabled && !$0.acpEnabled }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .compactMap { provider -> SpecModelGroup? in
                let models = provider.models
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .filter {
                        !DisabledModelStore.isDisabled(
                            providerID: provider.id,
                            modelID: $0,
                            defaults: defaults
                        )
                    }
                    .map { modelID in
                        option(
                            modelID: modelID,
                            providerID: provider.id,
                            providerName: provider.name,
                            source: .custom,
                            serverProviders: serverProviders,
                            override: overrides[ModelMetadataStore.key(
                                providerID: provider.id,
                                modelID: modelID
                            )],
                            supportsTools: provider.supportsTools
                        )
                    }
                guard !models.isEmpty else { return nil }
                return SpecModelGroup(
                    providerID: provider.id,
                    providerName: provider.name,
                    source: .custom,
                    models: models
                )
            }
        groups.append(contentsOf: customGroups)

        let localGroups = localProviders
            .filter(\.isEnabled)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .compactMap { provider -> SpecModelGroup? in
                let models = provider.models
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .filter {
                        !DisabledModelStore.isDisabled(
                            providerID: provider.id,
                            modelID: $0,
                            defaults: defaults
                        )
                    }
                    .map { modelID in
                        option(
                            modelID: modelID,
                            providerID: provider.id,
                            providerName: provider.displayName,
                            source: .local,
                            serverProviders: serverProviders,
                            override: overrides[ModelMetadataStore.key(
                                providerID: provider.id,
                                modelID: modelID
                            )],
                            supportsTools: nil
                        )
                    }
                guard !models.isEmpty else { return nil }
                return SpecModelGroup(
                    providerID: provider.id,
                    providerName: provider.displayName,
                    source: .local,
                    models: models
                )
            }
        groups.append(contentsOf: localGroups)

        return groups
    }

    /// The option matching a stored draft selection, if the provider/model is
    /// still available. A non-empty provider id must match exactly; an empty
    /// one falls back to the first model with that id for older drafts.
    static func option(
        providerID: String,
        modelID: String,
        in groups: [SpecModelGroup]
    ) -> SpecModelOption? {
        if !providerID.isEmpty {
            return groups.first(where: { $0.providerID == providerID })?
                .models.first(where: { $0.modelID == modelID })
        }
        return groups.lazy.flatMap { $0.models }.first(where: { $0.modelID == modelID })
    }

    /// Clears a preset the wizard cannot actually route: a disabled provider,
    /// a disabled model, or a chat-only provider that is not in the tree.
    /// A draft with an empty provider id is left alone so older drafts keep
    /// their app-wide fallback. Without this, the setup step would look
    /// configured and then fail with "unsupported route" on the first turn.
    static func pruneUnroutableSelection(
        providerID: inout String,
        modelID: inout String,
        groups: [SpecModelGroup]
    ) {
        guard !providerID.isEmpty else { return }
        guard option(providerID: providerID, modelID: modelID, in: groups) == nil else {
            return
        }
        providerID = ""
        modelID = ""
    }

    // MARK: - Providers

    private static func autoFreeGroup(
        provider: MyCoderAutoFreeProvider,
        defaults: UserDefaults
    ) -> SpecModelGroup {
        let live = provider.models
        let liveIDs = Set(live.map(\.id))
        let fallbackIDs = live.isEmpty
            ? MyCoderAutoFreeClient.freeModelIDs
            : []
        let orderedIDs = live.map(\.id) + fallbackIDs
            .filter { !liveIDs.contains($0) }

        var seen = Set<String>()
        let models = orderedIDs.compactMap { modelID -> SpecModelOption? in
            guard seen.insert(modelID).inserted else { return nil }
            guard !DisabledModelStore.isDisabled(
                providerID: provider.id,
                modelID: modelID,
                defaults: defaults
            ) else { return nil }
            let liveModel = live.first(where: { $0.id == modelID })
            return SpecModelOption(
                providerID: provider.id,
                providerName: provider.displayName,
                modelID: modelID,
                metadata: autoFreeMetadata(modelID: modelID, liveModel: liveModel)
            )
        }
        return SpecModelGroup(
            providerID: provider.id,
            providerName: provider.displayName,
            source: .autoFree,
            models: models
        )
    }

    // MARK: - Metadata

    private static func option(
        modelID: String,
        providerID: String,
        providerName: String,
        source: SpecModelMetadata.Source,
        serverProviders: [MimoProviderResponse],
        override: ModelMetadataOverride?,
        supportsTools: Bool?
    ) -> SpecModelOption {
        let catalogModel = ProviderSettingsLogic.model(for: modelID, in: serverProviders)
        let resolved = ModelMetadataResolver.resolve(
            modelID: modelID,
            providerID: providerID,
            serverModel: catalogModel,
            override: override
        )
        let context = resolved?.limit?.context
        let output = resolved?.limit?.output
        let capabilities = resolved?.capabilities
        let cost = resolved?.cost

        let metadata = SpecModelMetadata(
            source: source,
            displayName: resolved?.name ?? ModelGroupingLogic.splitModelID(modelID).name,
            contextWindow: context,
            effectiveContextWindow: ContextWindowCatalog.limit(for: modelID, reported: context),
            outputLimit: output,
            effectiveOutputLimit: ContextWindowCatalog.outputLimit(for: modelID, reported: output),
            reasoning: capabilities?.reasoning,
            toolCall: capabilities?.toolcall ?? supportsTools,
            plan: capabilities?.plan,
            vision: capabilities?.vision,
            imageGeneration: capabilities?.imagegen,
            costInput: cost?.input,
            costOutput: cost?.output,
            description: nil,
            isFree: (cost?.input ?? -1) == 0 && (cost?.output ?? -1) == 0
        )
        return SpecModelOption(
            providerID: providerID,
            providerName: providerName,
            modelID: modelID,
            metadata: metadata
        )
    }

    private static func autoFreeMetadata(
        modelID: String,
        liveModel: MyCoderAutoFreeClient.Model?
    ) -> SpecModelMetadata {
        let catalogModel = ModelMetadataCatalog.shared.lookup(modelID: modelID)
        let catalogCapabilities = catalogModel?.capabilities
        let context = liveModel?.contextLength ?? catalogModel?.limit?.context
        let output = catalogModel?.limit?.output
        let description = liveModel?.description
            ?? liveModel?.effectiveDescription
        return SpecModelMetadata(
            source: .autoFree,
            displayName: liveModel?.name ?? catalogModel?.name ?? modelID,
            contextWindow: context,
            effectiveContextWindow: ContextWindowCatalog.limit(for: modelID, reported: context),
            outputLimit: output,
            effectiveOutputLimit: ContextWindowCatalog.outputLimit(for: modelID, reported: output),
            reasoning: catalogCapabilities?.reasoning,
            toolCall: true,
            plan: catalogCapabilities?.plan,
            vision: catalogCapabilities?.vision,
            imageGeneration: catalogCapabilities?.imagegen,
            costInput: nil,
            costOutput: nil,
            description: description,
            isFree: true
        )
    }
}
