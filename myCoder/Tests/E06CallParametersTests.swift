import Testing
import Foundation
@testable import myCoder

/// E06 (FEATURE_TEST_REPORT): call parameters (temperature/max_tokens/top_p)
/// chosen in the model menu were LOST on the serve path (MessageSendOptions
/// body) and on the ACP path (ACPClient.sendChatCompletion/stream body) — the
/// direct OpenAI-compatible path was the only one that applied them. Раздел 9
/// п.49 requires parameters to actually reach the model for every provider.
@Suite("E06 — call parameters reach serve + ACP bodies")
struct E06CallParametersTests {

    private func params(temperature: Double = 0.7, maxTokens: Int = 2048, topP: Double = 0.9) -> ModelCallParameters {
        ModelCallParameters(temperature: temperature, maxTokens: maxTokens, topP: topP)
    }

    // MARK: Serve path (MessageSendOptions.requestBody)

    @Test("serve request body includes temperature/max_tokens/top_p when customized")
    func serveBodyIncludesParameters() {
        let options = MessageSendOptions(agent: "build", modelID: "m", providerID: "p")
        let body = options.requestBody(
            parts: [["type": "text", "text": "hi"]],
            parameters: params()
        )
        #expect(body["temperature"] as? Double == 0.7)
        #expect(body["max_tokens"] as? Int == 2048)
        #expect(body["top_p"] as? Double == 0.9)
    }

    @Test("serve body omits parameters when not customized (defaults)")
    func serveBodyOmitsDefaults() {
        let options = MessageSendOptions(agent: "build", modelID: "m", providerID: "p")
        let body = options.requestBody(parts: [["type": "text", "text": "hi"]], parameters: ModelCallParameters())
        #expect(body["temperature"] == nil)
        #expect(body["max_tokens"] == nil)
        #expect(body["top_p"] == nil)
    }

    // MARK: ACP path

    @Test("ACP sendChatCompletion body includes call parameters")
    func acpSendBodyIncludesParameters() async throws {
        // Build the body exactly as ACPClient does (body assembly is what we
        // assert); the network call itself is not made here.
        let fragment = ModelCallParametersStore.requestFragment(params())
        #expect(fragment["temperature"] as? Double == 0.7)
        #expect(fragment["max_tokens"] as? Int == 2048)
        #expect(fragment["top_p"] as? Double == 0.9)
        // The ACP body must merge the fragment (verified via ACPRequestBodyBuilder).
        let body = ACPRequestBodyBuilder.body(
            model: "m",
            messages: [ACPRequestMessage(role: "user", content: "hi")],
            agent: "build",
            variant: nil,
            parameters: params()
        )
        #expect(body["temperature"] as? Double == 0.7)
        #expect(body["max_tokens"] as? Int == 2048)
        #expect(body["top_p"] as? Double == 0.9)
    }

    @Test("ACP stream body includes call parameters")
    func acpStreamBodyIncludesParameters() {
        let body = ACPRequestBodyBuilder.streamBody(
            model: "m",
            messages: [ACPRequestMessage(role: "user", content: "hi")],
            agent: "build",
            variant: nil,
            parameters: params()
        )
        #expect(body["temperature"] as? Double == 0.7)
        #expect(body["max_tokens"] as? Int == 2048)
        #expect(body["stream"] as? Bool == true)
    }

    @Test("ACP body omits parameters when not customized")
    func acpBodyOmitsDefaults() {
        let body = ACPRequestBodyBuilder.body(
            model: "m",
            messages: [ACPRequestMessage(role: "user", content: "hi")],
            agent: "build",
            variant: nil,
            parameters: ModelCallParameters()
        )
        #expect(body["temperature"] == nil)
        #expect(body["max_tokens"] == nil)
    }
}
