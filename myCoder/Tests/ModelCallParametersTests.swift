import Testing
import Foundation
@testable import myCoder

@Suite("Model call parameters (plan Раздел 13 п.14)")
struct ModelCallParametersTests {

    @Test func emptyParamsNotCustomized() {
        #expect(!ModelCallParameters().isCustomized)
        #expect(ModelCallParameters(temperature: 0.7).isCustomized)
        #expect(ModelCallParameters(systemPrompt: "x").isCustomized)
        #expect(!ModelCallParameters(systemPrompt: "").isCustomized)
    }

    @Test func persistPerModel() {
        let d = UserDefaults(suiteName: "model-params-\(UUID().uuidString)")!
        ModelCallParametersStore.set(ModelCallParameters(temperature: 0.5, maxTokens: 2048), for: "gpt-4o", defaults: d)
        let loaded = ModelCallParametersStore.parameters(for: "gpt-4o", defaults: d)
        #expect(loaded.temperature == 0.5)
        #expect(loaded.maxTokens == 2048)
        // A different model is independent.
        #expect(ModelCallParametersStore.parameters(for: "claude", defaults: d).temperature == nil)
    }

    @Test func settingEmptyRemovesEntry() {
        let d = UserDefaults(suiteName: "model-params-\(UUID().uuidString)")!
        ModelCallParametersStore.set(ModelCallParameters(temperature: 0.5), for: "m", defaults: d)
        #expect(!ModelCallParametersStore.loadAll(defaults: d).isEmpty)
        ModelCallParametersStore.set(ModelCallParameters(), for: "m", defaults: d)  // all nil
        #expect(ModelCallParametersStore.loadAll(defaults: d).isEmpty)
    }

    @Test func whitespaceSystemPromptDoesNotCreateEntry() {
        let d = UserDefaults(suiteName: "model-params-\(UUID().uuidString)")!
        ModelCallParametersStore.set(ModelCallParameters(systemPrompt: "  \n\t "), for: "m", defaults: d)
        #expect(ModelCallParametersStore.loadAll(defaults: d).isEmpty)
    }

    @Test func requestFragmentOnlyIncludesSetKeys() {
        let frag = ModelCallParametersStore.requestFragment(
            ModelCallParameters(temperature: 0.3, maxTokens: 1000)
        )
        #expect(frag["temperature"] as? Double == 0.3)
        #expect(frag["max_tokens"] as? Int == 1000)
        #expect(frag["top_p"] == nil)
        #expect(frag["system"] == nil)
    }

    @Test func requestFragmentTrimsSystemPrompt() {
        let frag = ModelCallParametersStore.requestFragment(
            ModelCallParameters(systemPrompt: "  Be precise  ")
        )
        #expect(frag["system"] as? String == "Be precise")
    }

    @Test func requestFragmentEmptyForDefaults() {
        #expect(ModelCallParametersStore.requestFragment(ModelCallParameters()).isEmpty)
    }
}
