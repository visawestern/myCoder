import Foundation

extension AppState {
    /// Every model the user can switch to, with the provider it belongs to
    /// and its context window.
    ///
    /// The escape hatch after a model switch spans providers: the model with a
    /// larger window is often not in the current provider at all — a live run
    /// showed an empty list because only the current provider was searched.
    ///
    /// Providers and models the user switched off are left out: they are not
    /// a way out. Web providers are left out as well — they keep the history
    /// on the server and report no context window, so offering them would be
    /// a guess.
    var modelSwitchCompactionCandidates: [ModelSwitchCompactionLogic.Candidate] {
        var catalogs: [ModelSwitchCompactionLogic.ProviderModels] = []

        for provider in serverProviders where isProviderEnabled(provider.id) {
            catalogs.append(ModelSwitchCompactionLogic.ProviderModels(
                providerID: provider.id,
                providerName: provider.name,
                models: provider.models.keys
                    .filter { isModelEnabled(providerID: provider.id, modelID: $0) }
                    .sorted()
                    .map { modelID in
                        ModelSwitchCompactionLogic.ProviderModels.Model(
                            id: modelID,
                            window: ModelCapabilityLogic.effectiveContextWindow(
                                for: modelID,
                                in: serverProviders,
                                providerID: provider.id
                            )
                        )
                    }
            ))
        }

        for provider in customProviders where provider.isEnabled {
            catalogs.append(ModelSwitchCompactionLogic.ProviderModels(
                providerID: provider.id,
                providerName: provider.name,
                models: provider.models
                    .filter { isModelEnabled(providerID: provider.id, modelID: $0) }
                    .sorted()
                    .map { modelID in
                        ModelSwitchCompactionLogic.ProviderModels.Model(
                            id: modelID,
                            window: ModelCapabilityLogic.effectiveContextWindow(
                                for: modelID,
                                in: serverProviders,
                                providerID: provider.id
                            )
                        )
                    }
            ))
        }

        for provider in LocalProviderLogic.load(defaults: defaults) where provider.isEnabled {
            catalogs.append(ModelSwitchCompactionLogic.ProviderModels(
                providerID: provider.id,
                providerName: provider.displayName,
                models: provider.models
                    .filter { isModelEnabled(providerID: provider.id, modelID: $0) }
                    .sorted()
                    .map { modelID in
                        ModelSwitchCompactionLogic.ProviderModels.Model(
                            id: modelID,
                            window: ModelCapabilityLogic.effectiveContextWindow(
                                for: modelID,
                                in: serverProviders,
                                providerID: provider.id
                            )
                        )
                    }
            ))
        }

        return ModelSwitchCompactionLogic.candidates(from: catalogs)
    }
}
