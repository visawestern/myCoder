import Foundation
import Testing
@testable import myCoder

@Suite("SET-11: local provider model selection")
struct LocalModelSelectionLogicTests {
    @Test("only the active provider's selected model is marked")
    func selectionIsProviderScoped() {
        #expect(LocalModelSelectionLogic.isSelected("qwen", selectedProviderID: "ollama-1", activeProviderID: "ollama-1", selectedModel: "qwen"))
        #expect(!LocalModelSelectionLogic.isSelected("llama", selectedProviderID: "ollama-1", activeProviderID: "ollama-1", selectedModel: "qwen"))
        #expect(!LocalModelSelectionLogic.isSelected("qwen", selectedProviderID: "ollama-1", activeProviderID: "open-code-1", selectedModel: "qwen"))
    }

    @Test("tapping a catalog model returns that model")
    func tapSelectsModel() {
        #expect(LocalModelSelectionLogic.modelAfterTap("llama", catalog: ["qwen", "llama"], current: "qwen") == "llama")
        #expect(LocalModelSelectionLogic.modelAfterTap("missing", catalog: ["qwen", "llama"], current: "qwen") == "qwen")
    }

    @Test("provider switch is required before selecting its model")
    func providerSwitchesBeforeModel() {
        #expect(LocalModelSelectionLogic.shouldSwitchProvider(activeProviderID: "ollama-1", tappedProviderID: "open-code-1"))
        #expect(!LocalModelSelectionLogic.shouldSwitchProvider(activeProviderID: "ollama-1", tappedProviderID: "ollama-1"))
    }
}
