import Foundation

/// One-time clean slate for provider state.
///
/// User directive: the app must start from scratch — no provider rows, no
/// API keys and no model selections carried over from an earlier project or
/// an earlier build. The wipe runs exactly once (guarded by a marker key) and
/// only touches provider state; chats, projects and UI preferences stay.
enum ProviderCleanSlateReset {
    /// Marker written after the wipe so it never runs twice.
    static let markerKey = "com.mycoder.providerCleanSlate.v1"

    /// Persisted provider state that must not survive the clean slate.
    static let providerStateKeys: [String] = [
        // Server catalog + connection
        "com.mycoder.serverProviders",
        "com.mycoder.serverHost",
        "com.mycoder.serverPort",
        "com.mycoder.serverConnectionEnabled",
        // User-managed providers
        "com.mycoder.customProviders",
        "com.mycoder.localProviders",
        "com.mycoder.webProviders",
        // Per-provider switches
        "com.mycoder.disabledProviders",
        "com.mycoder.disabledModels",
        "com.mycoder.internalModels",
        "com.mycoder.modelCallParameters",
        "com.mycoder.modelMetadataOverrides",
        // Selections
        "com.mycoder.selectedModel",
        "com.mycoder.preferredModelID",
        "com.mycoder.selectedProviderID",
        "com.mycoder.preferredProviderID",
        "com.mycoder.selectedVariant",
        // Built-in free route state
        "com.mycoder.autoFree.model",
        "com.mycoder.autoFree.locked",
        "com.mycoder.autoFree.systemPrompt",
        // Misc provider bookkeeping
        "com.mycoder.providersChanged",
        "com.mycoder.webRemoteChatMappings",
    ]

    /// Prefixes of dynamic keys that belong to provider state.
    static let providerStatePrefixes: [String] = [
        "api_key_",
        "secret_",
        "encrypted_",
        "com.mycoder.toolResultFix.",
    ]

    /// Wipe once. Returns true when the wipe actually ran.
    @discardableResult
    static func runIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: markerKey) else { return false }
        wipe(defaults: defaults)
        defaults.set(true, forKey: markerKey)
        return true
    }

    /// Remove every persisted provider artefact (rows, credentials, switches,
    /// selections). Idempotent.
    static func wipe(defaults: UserDefaults = .standard) {
        for key in providerStateKeys {
            defaults.removeObject(forKey: key)
        }
        let dynamicKeys = defaults.dictionaryRepresentation().keys.filter { key in
            providerStatePrefixes.contains { key.hasPrefix($0) }
        }
        for key in dynamicKeys {
            defaults.removeObject(forKey: key)
        }
    }

    /// Test hook: forget that the wipe already happened.
    static func resetMarker(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: markerKey)
    }
}
