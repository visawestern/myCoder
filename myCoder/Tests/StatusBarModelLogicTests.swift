import Testing
@testable import myCoder

@Suite("Status bar effective model")
struct StatusBarModelLogicTests {
    @Test("uses effective web/Auto Free model when legacy selectedModel is empty")
    func effectiveModelWins() {
        #expect(StatusBarModelLogic.displayModel(
            selectedModel: "",
            effectiveModel: "gpt-4o"
        ) == "gpt-4o")
    }

    @Test("falls back to selected model and hides only when both are empty")
    func fallbackAndEmptyState() {
        #expect(StatusBarModelLogic.displayModel(
            selectedModel: "local-model",
            effectiveModel: ""
        ) == "local-model")
        #expect(StatusBarModelLogic.displayModel(
            selectedModel: "",
            effectiveModel: ""
        ) == nil)
    }
}
