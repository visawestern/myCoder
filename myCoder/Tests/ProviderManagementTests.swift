import Testing
import Foundation
@testable import myCoder

@Suite("Provider management")
struct ProviderManagementTests {
    private func customProvider(
        id: String = "opencode-zen",
        name: String = "OpenCode Zen",
        type: ProviderType = .openCodeZen,
        baseURL: String = OpenCodeZenCatalog.baseURL,
        apiKey: String = "",
        isEnabled: Bool = true,
        models: [String] = ["big-pickle", "beam-free"],
        requiresAPIKey: Bool = false
    ) -> CustomProvider {
        CustomProvider(
            id: id,
            name: name,
            type: type,
            baseURL: baseURL,
            apiKey: apiKey,
            isEnabled: isEnabled,
            models: models,
            requiresAPIKey: requiresAPIKey
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "ProviderManagementTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("Legacy anonymous Zen entry is dropped as a duplicate of the built-in Auto Free route")
    func legacyZenDuplicateIsRemoved() {
        let kept = ProviderDuplicationLogic.removingDuplicates([customProvider()])
        #expect(kept.isEmpty)
    }

    @Test("Zen entry with an API key is kept")
    func zenWithKeyIsKept() {
        let provider = customProvider(apiKey: "zen-key", requiresAPIKey: true)
        #expect(ProviderDuplicationLogic.removingDuplicates([provider]).count == 1)
    }

    @Test("Zen entry that exposes paid models is kept")
    func zenWithPaidModelsIsKept() {
        let provider = customProvider(models: ["deepseek-v4-pro"])
        #expect(ProviderDuplicationLogic.removingDuplicates([provider]).count == 1)
    }

    @Test("Zen entry on another endpoint is kept")
    func zenWithOtherBaseURLIsKept() {
        let provider = customProvider(baseURL: "https://example.com/v1")
        #expect(ProviderDuplicationLogic.removingDuplicates([provider]).count == 1)
    }

    @Test("Non-Zen providers are never treated as duplicates")
    func nonZenProvidersAreKept() {
        let provider = customProvider(
            id: "custom-1",
            name: "Custom",
            type: .openAI,
            baseURL: "https://api.example.com/v1",
            models: ["big-pickle"],
            requiresAPIKey: true
        )
        #expect(ProviderDuplicationLogic.removingDuplicates([provider]).count == 1)
    }

    @Test("Duplicate provider ids collapse into one entry")
    func duplicateOptionsAreCollapsed() {
        let options = [
            ProviderOption(id: "nvidia", name: "NVIDIA", isCustom: true, isConnected: true),
            ProviderOption(id: "NVIDIA", name: "NVIDIA copy", isCustom: true, isConnected: true),
            ProviderOption(id: "ollama-local", name: "Ollama", isCustom: true, isConnected: true)
        ]
        let deduplicated = ProviderDuplicationLogic.deduplicatedOptions(options)
        #expect(deduplicated.count == 2)
        #expect(deduplicated.first?.name == "NVIDIA")
    }

    @Test("Server and custom providers with the same name collapse to the manageable row")
    func duplicateNamesPreferCustomOption() {
        let options = [
            ProviderOption(id: "nvidia", name: "Nvidia", isCustom: false, isConnected: true),
            ProviderOption(id: "custom-nvidia", name: "  nvidia ", isCustom: true, isConnected: true)
        ]
        let deduplicated = ProviderDuplicationLogic.deduplicatedOptions(options)
        #expect(deduplicated.count == 1)
        #expect(deduplicated.first?.id == "custom-nvidia")
        #expect(deduplicated.first?.isCustom == true)
        #expect(ProviderDuplicationLogic.canonicalID(for: "nvidia", in: options) == "custom-nvidia")
    }

    @Test("Distinct provider names are not collapsed")
    func distinctNamesAreKept() {
        let options = [
            ProviderOption(id: "google", name: "Google", isCustom: false, isConnected: true),
            ProviderOption(id: "nvidia", name: "Nvidia", isCustom: false, isConnected: true),
            ProviderOption(id: "custom-nvidia", name: "Nvidia API", isCustom: true, isConnected: true)
        ]
        #expect(ProviderDuplicationLogic.deduplicatedOptions(options).count == 3)
    }

    @Test("Disabled models are tracked per provider")
    func disabledModelsAreStoredPerProvider() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        DisabledModelStore.setDisabled(true, providerID: "p1", modelID: "m1", defaults: defaults)
        #expect(DisabledModelStore.isDisabled(providerID: "p1", modelID: "m1", defaults: defaults))
        #expect(!DisabledModelStore.isDisabled(providerID: "p2", modelID: "m1", defaults: defaults))

        DisabledModelStore.setDisabled(false, providerID: "p1", modelID: "m1", defaults: defaults)
        #expect(!DisabledModelStore.isDisabled(providerID: "p1", modelID: "m1", defaults: defaults))
    }

    @Test("Disabled providers stay listed in Settings but not in the send picker")
    func disabledProvidersStayVisibleInSettings() {
        let provider = customProvider(
            id: "custom-1",
            name: "Custom",
            type: .openAI,
            baseURL: "https://api.example.com/v1",
            isEnabled: false,
            models: ["m1"],
            requiresAPIKey: true
        )
        #expect(ProviderSettingsLogic.allProviderOptions(serverProviders: [], customProviders: [provider]).isEmpty)
        let manageable = ProviderSettingsLogic.allProviderOptions(
            serverProviders: [],
            customProviders: [provider],
            includeDisabled: true
        )
        #expect(manageable.count == 1)
        #expect(manageable.first?.isConnected == false)
    }

    @Test("Disabled local providers stay listed in Settings but not in the send picker")
    func disabledLocalProvidersStayVisibleInSettings() {
        let local = LocalProviderConfig(id: "ollama-local", kind: .ollama, isEnabled: false, models: ["m1"])
        #expect(LocalProviderLogic.providerOptions(from: [local]).isEmpty)
        let manageable = LocalProviderLogic.providerOptions(from: [local], includeDisabled: true)
        #expect(manageable.count == 1)
        #expect(manageable.first?.isConnected == false)
    }

    @Test("Local providers can be edited, disabled, pruned and deleted")
    func localProviderLifecycle() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let config = LocalProviderConfig(id: "ollama-local", kind: .ollama, models: ["a", "b"])
        LocalProviderLogic.save([config], defaults: defaults)

        LocalProviderLogic.setEnabled(id: "ollama-local", isEnabled: false, defaults: defaults)
        #expect(LocalProviderLogic.load(defaults: defaults).first?.isEnabled == false)

        var updated = LocalProviderLogic.load(defaults: defaults)[0]
        updated.host = "10.0.0.5"
        updated.port = 4242
        LocalProviderLogic.update(updated, defaults: defaults)
        let reloaded = LocalProviderLogic.load(defaults: defaults)[0]
        #expect(reloaded.host == "10.0.0.5")
        #expect(reloaded.port == 4242)

        LocalProviderLogic.removeModel("a", from: "ollama-local", defaults: defaults)
        #expect(LocalProviderLogic.load(defaults: defaults).first?.models == ["b"])

        LocalProviderLogic.remove(id: "ollama-local", defaults: defaults)
        #expect(LocalProviderLogic.load(defaults: defaults).isEmpty)
    }

    @Test("Disabled models are hidden from the merged catalog")
    func disabledModelsAreHiddenFromMergedCatalog() {
        let provider = MimoProviderResponse(
            id: "srv",
            name: "Server",
            models: [
                "m1": MimoProviderModel(id: "m1", name: nil, capabilities: nil, variants: nil, limit: nil),
                "m2": MimoProviderModel(id: "m2", name: nil, capabilities: nil, variants: nil, limit: nil)
            ]
        )
        let merged = ProviderSettingsLogic.mergeModelIDs(
            serverProviders: [provider],
            customProviders: [],
            isDisabled: { _, modelID in modelID == "m1" }
        )
        #expect(merged == ["m2"])
    }

    @Test("NVIDIA provider points at the official OpenAI-compatible endpoint")
    func nvidiaProviderDefaults() {
        #expect(ProviderType.nvidia.defaultURL == "https://integrate.api.nvidia.com/v1")
        #expect(ProviderType.nvidia.endpointType == .openAI)
        #expect(ProviderEndpointLogic.defaultRequiresAPIKey(for: .nvidia))
        #expect(ProviderEndpointLogic.modelsURL(for: ProviderType.nvidia.defaultURL)
                == "https://integrate.api.nvidia.com/v1/models")
    }
}
