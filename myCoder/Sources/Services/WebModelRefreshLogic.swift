/// Atomic state transition for a completed web-model discovery refresh.
/// A refresh result is authoritative for auto-discovered models: stale entries
/// must not survive an empty or changed live snapshot. Explicit manual models
/// remain separate in `WebProviderConfig.manuallyAddedModels`.
enum WebModelRefreshLogic {
    static func replacing(config: WebProviderConfig,
                          with discoveredModels: [WebProviderModel]) -> WebProviderConfig {
        var updated = config
        var seen = Set<String>()
        let liveModels = discoveredModels.compactMap { original -> WebProviderModel? in
            guard let normalized = WebModelListParser.normalize(original.name, vendor: config.vendor),
                  seen.insert(normalized.lowercased()).inserted else { return nil }
            var model = original
            model.name = normalized
            // Capability probing can deliberately mark a visible candidate
            // inactive/unselectable. Preserve that evidence; the refresh must
            // not turn an unverified menu item into a sendable model.
            if model.discoveryStatus == .notDetected {
                model.discoveryStatus = .active
            }
            if !model.isLiveDiscovered {
                model.isLiveDiscovered = true
            }
            return model
        }

        // Audit 2026-09-06 (Claude live): the vendor model menu is
        // CONTEXT-DEPENDENT — the visible list depends on the currently
        // selected model (probing "Sonnet 4.6" hides "Sonnet 5"/"Haiku 4.5"
        // from that menu state). REPLACING the whole list on every refresh
        // destroyed previously verified models and shifted selectedModel to
        // whatever the last probe left active. Merge instead: fresh entries
        // update capabilities; previously verified selectable entries are
        // PRESERVED (annotated when absent from this scan) because a narrow
        // probe state is not proof of retirement.
        var merged: [String: WebProviderModel] = [:]
        for previous in config.discoveredModels {
            merged[previous.name.lowercased()] = previous
        }
        for model in liveModels {
            merged[model.name.lowercased()] = model
        }
        // Annotate previously selectable entries the scan did not show.
        for (key, value) in merged where !liveModels.contains(where: { $0.name.lowercased() == key }) && value.isSelectable {
            var hidden = value
            hidden.discoveryMessage = "Not visible in the latest menu scan (the vendor menu is context-dependent)."
            merged[key] = hidden
        }
        updated.discoveredModels = merged.values
            .sorted { $0.name < $1.name }
        updated.discoveredEffortLevels = Array(Set(updated.discoveredModels.flatMap(\.availableEfforts)))
            .sorted { $0.rawValue < $1.rawValue }
        // Keep the explicit selection when it is still a selectable model;
        // the menu's transient visibility must never rewrite the user's pick.
        if let kept = merged[config.selectedModel.lowercased()], kept.isSelectable {
            updated.selectedModel = config.selectedModel
        } else {
            updated.selectedModel = updated.allModels.first ?? ""
        }
        return updated
    }
}
