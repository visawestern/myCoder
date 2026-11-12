import Testing
import Foundation
@testable import myCoder

/// The composer dropdown builds all row metadata in one pass per open. The
/// old per-row path re-ran `InternalModelResolver.route` for every model —
/// for custom providers (OpenRouter) that meant a Keychain lookup per model,
/// which froze the dropdown on large catalogs (user report 2026-11-12).
@Suite("Model picker row metadata builder")
struct ModelPickerRowMetadataTests {

    private func provider(id: String = "p1", models: [String: MimoProviderModel]) -> MimoProviderResponse {
        MimoProviderResponse(id: id, name: "Provider", models: models)
    }

    @Test("Builds one metadata entry per model")
    func buildsEntryPerModel() {
        let metadata = ModelPickerRowMetadataBuilder.build(
            modelIDs: ["a", "b", "c"],
            providerID: "p1",
            selectedModel: "b",
            effectiveModel: "b",
            serverProviders: [],
            isInternal: { _ in false },
            canBeInternalForProvider: true
        )
        #expect(metadata.count == 3)
        #expect(metadata["b"]?.isSelected == true)
        #expect(metadata["a"]?.isSelected == false)
    }

    @Test("isInternal callback is consulted per model")
    func isInternalUsesCallback() {
        let metadata = ModelPickerRowMetadataBuilder.build(
            modelIDs: ["a", "b"],
            providerID: "p1",
            selectedModel: "",
            effectiveModel: "",
            serverProviders: [],
            isInternal: { $0 == "a" },
            canBeInternalForProvider: true
        )
        #expect(metadata["a"]?.isInternal == true)
        #expect(metadata["b"]?.isInternal == false)
    }

    @Test("canBeInternal is shared across every row, not computed per row")
    func canBeInternalIsShared() {
        let metadata = ModelPickerRowMetadataBuilder.build(
            modelIDs: Array(repeating: "m", count: 500).enumerated().map { "m\($0.offset)" },
            providerID: "p1",
            selectedModel: "",
            effectiveModel: "",
            serverProviders: [],
            isInternal: { _ in false },
            canBeInternalForProvider: false
        )
        #expect(metadata.values.allSatisfy { $0.canBeInternal == false })
        #expect(metadata.count == 500)
    }

    @Test("Badges and context window come from server metadata")
    func badgesAndContextFromServerMetadata() {
        let providers = [
            provider(models: [
                "m1": MimoProviderModel(
                    id: "m1",
                    capabilities: MimoModelCapabilities(reasoning: true, toolcall: true),
                    limit: MimoModelLimit(context: 128_000, output: nil)
                )
            ])
        ]
        let metadata = ModelPickerRowMetadataBuilder.build(
            modelIDs: ["m1"],
            providerID: "p1",
            selectedModel: "",
            effectiveModel: "",
            serverProviders: providers,
            isInternal: { _ in false },
            canBeInternalForProvider: false
        )
        let m1 = metadata["m1"]
        #expect(m1?.context == 128_000)
        #expect(m1?.badges.map(\.kind).contains(.thinking) == true)
        #expect(m1?.badges.map(\.kind).contains(.tools) == true)
    }

    @Test("canBeInternal is true for an enabled custom provider")
    func canBeInternalCustomEnabled() {
        let custom = CustomProvider(id: "or", name: "OpenRouter", type: .openRouter, baseURL: "https://openrouter.ai/api/v1", apiKey: "k", models: [], isEnabled: true)
        #expect(ModelPickerRowMetadataBuilder.canBeInternalForProvider(
            providerID: "or",
            modelIDs: ["a"],
            customProviders: [custom],
            localProviders: [],
            serverProviders: []
        ))
    }

    @Test("canBeInternal is false for a disabled custom provider")
    func canBeInternalCustomDisabled() {
        let custom = CustomProvider(id: "or", name: "OpenRouter", type: .openRouter, baseURL: "https://openrouter.ai/api/v1", apiKey: "k", models: [], isEnabled: false)
        #expect(!ModelPickerRowMetadataBuilder.canBeInternalForProvider(
            providerID: "or",
            modelIDs: ["a"],
            customProviders: [custom],
            localProviders: [],
            serverProviders: []
        ))
    }

    @Test("canBeInternal is true for an enabled local provider")
    func canBeInternalLocalEnabled() {
        let local = LocalProviderConfig(id: "ollama", kind: .ollama, host: "127.0.0.1", port: 11434, models: [], isEnabled: true)
        #expect(ModelPickerRowMetadataBuilder.canBeInternalForProvider(
            providerID: "ollama",
            modelIDs: ["a"],
            customProviders: [],
            localProviders: [local],
            serverProviders: []
        ))
    }

    @Test("canBeInternal is true for a server catalog provider")
    func canBeInternalServerProvider() {
        let servers = [MimoProviderResponse(id: "nvidia", name: "NVIDIA", models: [:])]
        #expect(ModelPickerRowMetadataBuilder.canBeInternalForProvider(
            providerID: "nvidia",
            modelIDs: ["a"],
            customProviders: [],
            localProviders: [],
            serverProviders: servers
        ))
    }

    @Test("canBeInternal is false for empty model list or provider")
    func canBeInternalEmptyCases() {
        #expect(!ModelPickerRowMetadataBuilder.canBeInternalForProvider(
            providerID: "or",
            modelIDs: [],
            customProviders: [],
            localProviders: [],
            serverProviders: []
        ))
        #expect(!ModelPickerRowMetadataBuilder.canBeInternalForProvider(
            providerID: "",
            modelIDs: ["a"],
            customProviders: [],
            localProviders: [],
            serverProviders: []
        ))
    }
}
