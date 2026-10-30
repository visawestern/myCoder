import Testing
@testable import myCoder

@Suite("Send API response metadata")
struct SendAPIResponseLogicTests {
    @Test("API response reports the effective model")
    func effectiveModelWins() {
        #expect(SendAPIResponseLogic.modelID(
            selectedModel: "",
            effectiveModel: "qwen-max"
        ) == "qwen-max")
    }

    @Test("API response falls back to legacy model for direct routes")
    func legacyModelFallback() {
        #expect(SendAPIResponseLogic.modelID(
            selectedModel: "llama3",
            effectiveModel: ""
        ) == "llama3")
    }
}
