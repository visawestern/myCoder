import Testing
@testable import myCoder

@Suite("Model selection presentation")
struct ModelSelectionPresentationLogicTests {
    @Test("effective model drives visible selector label and selected-row identity")
    func effectiveModelPresentation() {
        #expect(ModelSelectionPresentationLogic.displayModel(
            selectedModel: "",
            effectiveModel: "qwen-max"
        ) == "qwen-max")
        #expect(ModelSelectionPresentationLogic.isSelected(
            candidate: "qwen-max",
            selectedModel: "",
            effectiveModel: "qwen-max"
        ))
    }

    @Test("parameter controls use effective model key and appear for it")
    func effectiveModelParameterKey() {
        #expect(ModelSelectionPresentationLogic.parameterModelID(
            selectedModel: "",
            effectiveModel: "qwen-max"
        ) == "qwen-max")
        #expect(ModelSelectionPresentationLogic.shouldShowParameters(
            selectedModel: "",
            effectiveModel: "qwen-max"
        ))
    }

    @Test("empty effective and selected models keep placeholder and hide parameters")
    func emptyModelState() {
        #expect(ModelSelectionPresentationLogic.displayModel(
            selectedModel: "",
            effectiveModel: ""
        ) == nil)
        #expect(!ModelSelectionPresentationLogic.shouldShowParameters(
            selectedModel: "",
            effectiveModel: ""
        ))
    }
}
