import Foundation
import Testing
@testable import myCoder

struct ModelMetadataCatalogTests {
    private let fixture = """
    {
      "version": 1,
      "models": {
        "gpt-4o": {
          "id": "gpt-4o",
          "name": "GPT-4o",
          "context": 128000,
          "output": 16384,
          "reasoning": false,
          "toolCall": true,
          "vision": true,
          "imageGen": false,
          "efforts": [],
          "costInput": 2.5,
          "costOutput": 10
        },
        "claude-sonnet-4": {
          "id": "claude-sonnet-4",
          "name": "Claude Sonnet 4",
          "context": 200000,
          "output": 64000,
          "reasoning": true,
          "toolCall": true,
          "vision": true,
          "efforts": ["low", "medium", "high"]
        }
      }
    }
    """.data(using: .utf8)!

    @Test func looksUpExactAndCaseInsensitive() {
        let catalog = ModelMetadataCatalog(data: fixture)
        #expect(catalog.lookup(modelID: "gpt-4o")?.limit?.context == 128_000)
        #expect(catalog.lookup(modelID: "GPT-4O")?.name == "GPT-4o")
    }

    @Test func looksUpProviderPrefixedAndFreeAlias() {
        let catalog = ModelMetadataCatalog(data: fixture)
        #expect(catalog.lookup(modelID: "openai/gpt-4o")?.limit?.context == 128_000)
        #expect(catalog.lookup(modelID: "openai/gpt-4o:free")?.limit?.context == 128_000)
        #expect(catalog.lookup(modelID: "gpt-4o-free")?.limit?.context == 128_000)
    }

    @Test func keepsEffortLevelsAndCapabilities() {
        let catalog = ModelMetadataCatalog(data: fixture)
        let model = catalog.lookup(modelID: "claude-sonnet-4")
        #expect(model?.capabilities?.reasoning == true)
        #expect(model?.capabilities?.vision == true)
        #expect(model?.capabilities?.toolcall == true)
        #expect(model?.limit?.context == 200_000)
        #expect(model?.variants?.keys.sorted() == ["high", "low", "medium"])
    }

    @Test func overrideWinsAndFillsMissingValues() {
        let catalog = ModelMetadataCatalog(data: fixture)
        let override = ModelMetadataOverride(
            context: 32_000,
            output: nil,
            reasoning: true,
            toolCall: false,
            vision: nil,
            imageGen: nil,
            plan: true,
            efforts: ["default", "max"]
        )
        let model = ModelMetadataResolver.resolve(
            modelID: "gpt-4o",
            providerID: "custom-1",
            serverModel: nil,
            catalog: catalog,
            override: override
        )
        #expect(model?.limit?.context == 32_000)
        #expect(model?.limit?.output == 16_384)
        #expect(model?.capabilities?.reasoning == true)
        #expect(model?.capabilities?.toolcall == false)
        #expect(model?.capabilities?.vision == true)
        #expect(model?.capabilities?.plan == true)
        #expect(model?.variants?.keys.sorted() == ["default", "max"])
    }

    @Test func overrideWorksWithoutCatalogEntry() {
        let catalog = ModelMetadataCatalog(data: fixture)
        let override = ModelMetadataOverride(context: 8_192, output: 2_048, efforts: ["low"])
        let model = ModelMetadataResolver.resolve(
            modelID: "local/unknown",
            providerID: "local-1",
            serverModel: nil,
            catalog: catalog,
            override: override
        )
        #expect(model?.id == "local/unknown")
        #expect(model?.limit?.context == 8_192)
        #expect(model?.limit?.output == 2_048)
        #expect(model?.variants?.keys.sorted() == ["low"])
    }

    @Test func storeRoundTripsPerProvider() {
        let suite = "ModelMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let override = ModelMetadataOverride(context: 64_000, reasoning: true, efforts: ["low", "high"])
        ModelMetadataStore.set(override, providerID: "p1", modelID: "m1", defaults: defaults)
        #expect(ModelMetadataStore.override(providerID: "p1", modelID: "m1", defaults: defaults) == override)
        #expect(ModelMetadataStore.override(providerID: "p2", modelID: "m1", defaults: defaults) == nil)

        ModelMetadataStore.clear(providerID: "p1", modelID: "m1", defaults: defaults)
        #expect(ModelMetadataStore.override(providerID: "p1", modelID: "m1", defaults: defaults) == nil)
    }
}
