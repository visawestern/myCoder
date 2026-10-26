import Testing
import Foundation
@testable import myCoder

@Suite("Internal models — server/local routing and catalog")
struct InternalModelResolverTests {

    private func serverProvider(id: String, name: String, models: [String]) -> MimoProviderResponse {
        var catalog: [String: MimoProviderModel] = [:]
        for model in models { catalog[model] = MimoProviderModel(id: model) }
        return MimoProviderResponse(id: id, name: name, models: catalog)
    }

    @Test func availableModelsIncludesServerAndSupportedLocalModels() {
        let custom = CustomProvider(id: "custom", name: "Custom", type: .openAI,
                                    baseURL: "https://api.example.com", isEnabled: true,
                                    models: ["custom-model"])
        let local = LocalProviderConfig(kind: .strata, models: ["strata-model"])
        let server = serverProvider(id: "google", name: "Google", models: ["gemini-flash-latest"])

        let refs = InternalModelResolver.availableModels(
            customProviders: [custom],
            localProviders: [local],
            freeModels: ["free-model"],
            serverProviders: [server]
        )

        #expect(refs.contains(InternalModelRef(providerID: "custom", modelID: "custom-model")))
        #expect(refs.contains(InternalModelRef(providerID: local.id, modelID: "strata-model")))
        #expect(refs.contains(InternalModelRef(providerID: "google", modelID: "gemini-flash-latest")))
        #expect(refs.contains(InternalModelRef(providerID: MyCoderAutoFreeProvider.builtInID, modelID: "free-model")))
    }

    @Test func serverModelRoutesThroughOpenCodeServe() {
        let server = serverProvider(id: "google", name: "Google", models: ["gemini-flash-latest"])
        let ref = InternalModelRef(providerID: "google", modelID: "gemini-flash-latest")
        let route = InternalModelResolver.route(
            for: ref,
            customProviders: [],
            localProviders: [],
            serverProviders: [server],
            serverBaseURL: "http://127.0.0.1:4096"
        )
        #expect(route == .openCodeServe(
            baseURL: "http://127.0.0.1:4096",
            headers: [:],
            providerID: "google",
            model: "gemini-flash-latest"
        ))
    }

    @Test func strataModelRoutesThroughOpenAIV1() {
        let local = LocalProviderConfig(kind: .strata, host: "127.0.0.1", port: 8399, models: ["strata-model"])
        let ref = InternalModelRef(providerID: local.id, modelID: "strata-model")
        let route = InternalModelResolver.route(
            for: ref,
            customProviders: [],
            localProviders: [local],
            serverProviders: []
        )
        #expect(route == .openAICompatible(
            baseURL: "http://127.0.0.1:8399/v1",
            apiKey: nil,
            model: "strata-model"
        ))
    }

    @Test func displayNameResolvesServerProviderName() {
        let server = serverProvider(id: "google", name: "Google", models: ["gemini-flash-latest"])
        let ref = InternalModelRef(providerID: "google", modelID: "gemini-flash-latest")
        let name = InternalModelResolver.displayName(
            for: ref,
            customProviders: [],
            localProviders: [],
            serverProviders: [server]
        )
        #expect(name == "Google")
    }

    @Test func serverCatalogAndAddressPersistForBackgroundWork() {
        let defaults = UserDefaults(suiteName: "test-server-catalog-\(UUID().uuidString)")!
        let server = serverProvider(id: "google", name: "Google", models: ["gemini-flash-latest"])
        ServerProviderCatalogStore.save([server], defaults: defaults)
        ServerProviderCatalogStore.saveConnection(host: "127.0.0.1", port: 4096, defaults: defaults)

        #expect(ServerProviderCatalogStore.load(defaults: defaults).first?.id == "google")
        #expect(ServerProviderCatalogStore.serverBaseURL(defaults: defaults) == "http://127.0.0.1:4096")
    }

    @Test func internalStoreTogglesModel() {
        let defaults = UserDefaults(suiteName: "test-internal-store-\(UUID().uuidString)")!
        let store = InternalModelStore(defaults: defaults)
        let ref = InternalModelRef(providerID: "google", modelID: "gemini-flash-latest")

        #expect(!store.contains(ref))
        store.add(ref)
        #expect(store.contains(ref))
        store.remove(ref)
        #expect(!store.contains(ref))
    }
}
