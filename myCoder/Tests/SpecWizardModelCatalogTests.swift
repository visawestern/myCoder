import Foundation
import Testing
@testable import myCoder

@MainActor
@Suite("Spec wizard model catalog")
struct SpecWizardModelCatalogTests {

    private func defaults() -> UserDefaults {
        let suite = "spec-wizard-model-catalog-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func customProvider(
        id: String,
        name: String,
        models: [String],
        isEnabled: Bool = true,
        acpEnabled: Bool = false
    ) -> CustomProvider {
        CustomProvider(
            id: id,
            name: name,
            type: .openAI,
            baseURL: "https://example.test/v1",
            isEnabled: isEnabled,
            models: models,
            acpEnabled: acpEnabled
        )
    }

    @Test("The tree groups models under their provider and hides disabled entries")
    func groupsAndFilters() {
        let defaults = defaults()
        DisabledModelStore.setDisabled(
            true,
            providerID: "custom-1",
            modelID: "hidden-model",
            defaults: defaults
        )

        let groups = SpecWizardModelCatalog.groups(
            serverProviders: [],
            customProviders: [
                customProvider(id: "custom-1", name: "Acme", models: ["gpt-4o", "hidden-model"]),
                customProvider(id: "custom-off", name: "Off", models: ["m1"], isEnabled: false),
                customProvider(id: "custom-acp", name: "ACP", models: ["m2"], acpEnabled: true)
            ],
            localProviders: [
                LocalProviderConfig(
                    id: "local-1",
                    kind: .ollama,
                    name: "Local Ollama",
                    isEnabled: true,
                    models: ["llama3.2:3b"]
                ),
                LocalProviderConfig(
                    id: "local-off",
                    kind: .ollama,
                    name: "Off Local",
                    isEnabled: false,
                    models: ["llama3.2:3b"]
                )
            ],
            defaults: defaults
        )

        #expect(groups.map(\.providerID) == ["custom-1", "local-1"])
        #expect(groups[0].models.map(\.modelID) == ["gpt-4o"])
        #expect(groups[1].models.map(\.modelID) == ["llama3.2:3b"])
        #expect(groups.allSatisfy { !$0.models.isEmpty })
    }

    @Test("Custom models get catalog metadata and keep the provider tool setting")
    func customMetadata() throws {
        let defaults = defaults()
        let groups = SpecWizardModelCatalog.groups(
            serverProviders: [],
            customProviders: [
                customProvider(id: "custom-1", name: "Acme", models: ["gpt-4o"])
            ],
            localProviders: [],
            defaults: defaults
        )
        let option = try #require(
            SpecWizardModelCatalog.option(
                providerID: "custom-1",
                modelID: "gpt-4o",
                in: groups
            )
        )
        #expect(option.metadata.displayName == "gpt-4o")
        #expect(option.metadata.contextWindow == 128_000)
        #expect(option.metadata.outputLimit == 16_384)
        #expect(option.metadata.reasoning == false)
        #expect(option.metadata.vision == true)
        #expect(option.metadata.toolCall == true)
        #expect(option.metadata.costInput == 2.5)
        #expect(option.metadata.costOutput == 10)
        #expect(option.metadata.isFree == false)
    }

    @Test("A user metadata override is reflected in the hover card data")
    func overrideMetadata() throws {
        let defaults = defaults()
        ModelMetadataStore.set(
            ModelMetadataOverride(context: 64_000, vision: false),
            providerID: "custom-1",
            modelID: "gpt-4o",
            defaults: defaults
        )
        let groups = SpecWizardModelCatalog.groups(
            serverProviders: [],
            customProviders: [
                customProvider(id: "custom-1", name: "Acme", models: ["gpt-4o"])
            ],
            localProviders: [],
            defaults: defaults
        )
        let option = try #require(
            SpecWizardModelCatalog.option(
                providerID: "custom-1",
                modelID: "gpt-4o",
                in: groups
            )
        )
        #expect(option.metadata.contextWindow == 64_000)
        #expect(option.metadata.vision == false)
        #expect(option.metadata.reasoning == false)
    }

    @Test("Options resolve by provider first, then by model id for legacy drafts")
    func optionLookup() throws {
        let defaults = defaults()
        let groups = SpecWizardModelCatalog.groups(
            serverProviders: [],
            customProviders: [
                customProvider(id: "custom-1", name: "Acme", models: ["shared"]),
                customProvider(id: "custom-2", name: "Beta", models: ["shared"])
            ],
            localProviders: [],
            defaults: defaults
        )

        let exact = try #require(SpecWizardModelCatalog.option(
            providerID: "custom-2",
            modelID: "shared",
            in: groups
        ))
        #expect(exact.providerID == "custom-2")

        let legacy = try #require(SpecWizardModelCatalog.option(
            providerID: "",
            modelID: "shared",
            in: groups
        ))
        #expect(legacy.providerID == "custom-1")

        #expect(SpecWizardModelCatalog.option(
            providerID: "custom-2",
            modelID: "missing",
            in: groups
        ) == nil)
    }

    @Test("A preset outside the wizard tree is cleared, a routable one is kept")
    func prunePreset() {
        let defaults = defaults()
        let groups = SpecWizardModelCatalog.groups(
            serverProviders: [],
            customProviders: [
                customProvider(id: "custom-1", name: "Acme", models: ["gpt-4o"])
            ],
            localProviders: [],
            defaults: defaults
        )

        var providerID = "custom-1"
        var modelID = "gpt-4o"
        SpecWizardModelCatalog.pruneUnroutableSelection(
            providerID: &providerID,
            modelID: &modelID,
            groups: groups
        )
        #expect(providerID == "custom-1")
        #expect(modelID == "gpt-4o")

        // A web/ACP/MiMo-serve provider never appears in the tree.
        providerID = "web-chat"
        modelID = "gpt-4o"
        SpecWizardModelCatalog.pruneUnroutableSelection(
            providerID: &providerID,
            modelID: &modelID,
            groups: groups
        )
        #expect(providerID == "")
        #expect(modelID == "")

        // Legacy drafts without a provider keep their app-wide fallback.
        providerID = ""
        modelID = "gpt-4o"
        SpecWizardModelCatalog.pruneUnroutableSelection(
            providerID: &providerID,
            modelID: &modelID,
            groups: groups
        )
        #expect(providerID == "")
        #expect(modelID == "gpt-4o")
    }
}
