import Testing
@testable import myCoder

@Suite("WEB-09 web selection reconciliation")
struct WebSelectionReconciliationLogicTests {
    @Test("destination provider selection beats a shared global preference")
    func destinationModelWinsOverGlobalPreference() {
        let config = WebProviderConfig(
            vendor: .qwen,
            selectedModel: "qwen-thinking",
            discoveredModels: [
                WebProviderModel(name: "shared-model"),
                WebProviderModel(name: "qwen-thinking")
            ]
        )

        let restored = WebSelectionReconciliationLogic.modelForRestore(
            config: config,
            globalPreferredModel: "shared-model",
            availableModels: config.allModels
        )

        #expect(restored == "qwen-thinking")
    }

    @Test("unsupported persisted effort falls back to a live model effort")
    func unsupportedEffortFallsBackToLiveCapability() {
        let config = WebProviderConfig(
            vendor: .qwen,
            selectedModel: "live-model",
            effort: .low,
            discoveredModels: [
                WebProviderModel(name: "live-model", availableEfforts: [.high])
            ]
        )
        let resolved = WebSelectionReconciliationLogic.effortForModel(
            config: config,
            modelID: "live-model",
            availableEfforts: [.high]
        )
        #expect(resolved == .high)
    }

    @Test("model without effort capability resolves to no effort")
    func modelWithoutEffortResolvesToNil() {
        let config = WebProviderConfig(
            vendor: .qwen,
            selectedModel: "plain-model",
            effort: .high,
            discoveredModels: [WebProviderModel(name: "plain-model", availableEfforts: [])]
        )
        #expect(WebSelectionReconciliationLogic.effortForModel(
            config: config,
            modelID: "plain-model",
            availableEfforts: []
        ) == nil)
    }

    @Test("stale destination selection may fall back to global model")
    func staleDestinationFallsBackToGlobalPreference() {
        let config = WebProviderConfig(
            vendor: .kimi,
            selectedModel: "removed-model",
            discoveredModels: [WebProviderModel(name: "shared-model")]
        )

        let restored = WebSelectionReconciliationLogic.modelForRestore(
            config: config,
            globalPreferredModel: "shared-model",
            availableModels: config.allModels
        )

        #expect(restored == "shared-model")
    }
}
