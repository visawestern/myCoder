import Testing
@testable import myCoder

@Suite("WEB-06 effective web model")
struct WebProviderEffectiveModelLogicTests {
    @Test("stale persisted model falls back to a discovered model")
    func staleModelFallsBack() {
        let config = WebProviderConfig(
            vendor: .kimi,
            selectedModel: "removed-model",
            discoveredModels: [WebProviderModel(name: "live-model")]
        )
        #expect(WebProviderSelectionLogic.effectiveSelectedModel(for: config) == "live-model")
    }

    @Test("valid persisted model remains selected")
    func validModelRemainsSelected() {
        let config = WebProviderConfig(
            vendor: .qwen,
            selectedModel: "live-model",
            discoveredModels: [WebProviderModel(name: "live-model"), WebProviderModel(name: "other")]
        )
        #expect(WebProviderSelectionLogic.effectiveSelectedModel(for: config) == "live-model")
    }
}
