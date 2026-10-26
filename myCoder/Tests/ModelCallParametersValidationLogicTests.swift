import Testing
@testable import myCoder

@Suite("INP-14 model parameter validation")
struct ModelCallParametersValidationLogicTests {
    @Test("valid values produce a customized parameter set")
    func validValues() {
        let params = ModelCallParametersValidationLogic.parse(
            temperature: "0.7",
            maxTokens: "2048",
            topP: "0.9",
            systemPrompt: "Be precise"
        )
        #expect(params == ModelCallParameters(temperature: 0.7, maxTokens: 2048, topP: 0.9, systemPrompt: "Be precise"))
    }

    @Test("system prompt normalization trims meaningful text")
    func systemPromptIsTrimmed() {
        let params = ModelCallParametersValidationLogic.parse(
            temperature: "",
            maxTokens: "",
            topP: "",
            systemPrompt: "  Be precise  "
        )
        #expect(params?.systemPrompt == "Be precise")
    }

    @Test("blank numeric fields remain provider defaults")
    func blanksAreUnset() {
        let params = ModelCallParametersValidationLogic.parse(
            temperature: "",
            maxTokens: "",
            topP: "",
            systemPrompt: ""
        )
        #expect(params == ModelCallParameters())
    }

    @Test("temperature and top-p outside their documented ranges are rejected")
    func floatingPointRangesAreEnforced() {
        #expect(ModelCallParametersValidationLogic.parse(temperature: "2.1", maxTokens: "100", topP: "0.5", systemPrompt: "") == nil)
        #expect(ModelCallParametersValidationLogic.parse(temperature: "0.5", maxTokens: "100", topP: "-0.1", systemPrompt: "") == nil)
    }

    @Test("max tokens must be a positive integer")
    func maxTokensIsPositiveInteger() {
        #expect(ModelCallParametersValidationLogic.parse(temperature: "0.5", maxTokens: "0", topP: "0.5", systemPrompt: "") == nil)
        #expect(ModelCallParametersValidationLogic.parse(temperature: "0.5", maxTokens: "12.5", topP: "0.5", systemPrompt: "") == nil)
    }
}
