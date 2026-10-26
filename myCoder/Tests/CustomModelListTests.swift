import Testing
import Foundation
@testable import myCoder

@Suite("Custom model list — rename survives refresh", .serialized)
struct CustomModelListTests {

    private func isolatedDefaults(name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeProvider(models: [String]) -> CustomProvider {
        CustomProvider(
            name: "Test Provider",
            type: .openAI,
            baseURL: "https://example.invalid/v1",
            models: models
        )
    }

    @Test("Merged list unions discovered and manual entries, hides removed")
    func mergeRule() {
        var provider = makeProvider(models: [])
        provider.customModels = ["my-custom-model"]
        provider.hiddenModels = ["gpt-4"]

        let merged = CustomModelListLogic.mergedModels(
            provider: provider,
            discovered: ["gpt-4", "gpt-3.5", "my-custom-model"]
        )
        #expect(merged == ["gpt-3.5", "my-custom-model"])
    }

    @Test("Rename updates the list and survives a refresh merge")
    func renameSurvivesRefresh() {
        let appState = AppState(host: "127.0.0.1", port: 0, defaults: isolatedDefaults(name: "com.mycoder.tests.model-rename"))
        let provider = makeProvider(models: ["gpt-4", "gpt-3.5"])
        appState.addCustomProvider(provider)

        appState.renameCustomModel(providerID: provider.id, modelID: "gpt-4", to: "My GPT")
        let renamed = appState.customProviders.first { $0.id == provider.id }
        #expect(renamed?.models.contains("My GPT") == true)
        #expect(renamed?.models.contains("gpt-4") == false)
        #expect(renamed?.customModels.contains("My GPT") == true)
        #expect(renamed?.hiddenModels.contains("gpt-4") == true)

        let merged = CustomModelListLogic.mergedModels(provider: renamed!, discovered: ["gpt-4", "gpt-3.5"])
        #expect(merged == ["My GPT", "gpt-3.5"])

        // Deleting a discovered model must keep it hidden after refresh too.
        appState.removeModel("gpt-3.5", from: provider.id)
        let cleaned = appState.customProviders.first { $0.id == provider.id }
        let cleanedMerged = CustomModelListLogic.mergedModels(provider: cleaned!, discovered: ["gpt-4", "gpt-3.5"])
        #expect(cleanedMerged == ["My GPT"])
    }

    @Test("Clone and custom add append manual entries")
    func cloneAndAdd() {
        let appState = AppState(host: "127.0.0.1", port: 0, defaults: isolatedDefaults(name: "com.mycoder.tests.model-clone"))
        let provider = makeProvider(models: ["m1"])
        appState.addCustomProvider(provider)

        appState.cloneCustomModel(providerID: provider.id, modelID: "m1", newName: "m1-copy")
        appState.addCustomModel(providerID: provider.id, modelID: "totally-custom")

        let updated = appState.customProviders.first { $0.id == provider.id }
        #expect(updated?.models == ["m1", "m1-copy", "totally-custom"])
        #expect(updated?.customModels.contains("m1-copy") == true)
        #expect(updated?.customModels.contains("totally-custom") == true)

        // Duplicate clone is rejected.
        appState.cloneCustomModel(providerID: provider.id, modelID: "m1", newName: "m1-copy")
        let after = appState.customProviders.first { $0.id == provider.id }
        #expect(after?.models.filter { $0 == "m1-copy" }.count == 1)
    }

    @Test("CustomProvider decodes legacy JSON without the new fields")
    func legacyDecoding() throws {
        let json = """
        {"id":"p1","name":"Legacy","type":"OpenAI Compatible","baseURL":"https://example.invalid","apiKey":"","isEnabled":true,"models":["m1"],"supportsTools":true,"acpEnabled":false,"requiresAPIKey":true}
        """
        let provider = try JSONDecoder().decode(CustomProvider.self, from: Data(json.utf8))
        #expect(provider.customModels.isEmpty)
        #expect(provider.hiddenModels.isEmpty)
        #expect(provider.models == ["m1"])
    }
}
