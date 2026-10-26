import Testing
import Foundation
@testable import myCoder

@Suite("MyCoderAutoFreeProvider — anonymous OpenCode free catalog")
struct MyCoderAutoFreeProviderTests {

    @Test("provider uses the renamed built-in ID and Big Pickle default")
    func providerIdentityAndDefaultModel() {
        let provider = MyCoderAutoFreeProvider()

        #expect(MyCoderAutoFreeProvider.builtInID == "mycoder-auto-free")
        #expect(provider.displayName == "OpenCode Zen")
        #expect(provider.selectedModel == "big-pickle")
        #expect(provider.isReady == false)
        #expect(MyCoderAutoFreeClient.defaultModelID == "big-pickle")
    }

    @Test("free allow-list contains Big Pickle and official alternatives only")
    func freeAllowList() {
        #expect(MyCoderAutoFreeClient.freeModelIDs.first == "big-pickle")
        #expect(MyCoderAutoFreeClient.freeModelIDs.contains("deepseek-v4-flash-free"))
        #expect(MyCoderAutoFreeClient.freeModelIDs.contains("mimo-v2.5-free"))
        #expect(MyCoderAutoFreeClient.freeModelIDs.contains("muse-spark-1.3-contributor-free"))
        #expect(!MyCoderAutoFreeClient.freeModelIDs.contains("claude-opus-5"))
        #expect(!MyCoderAutoFreeClient.freeModelIDs.contains("gpt-5.5"))
    }

    @Test("anonymous provider starts without a synthetic model")
    func noSyntheticModelBeforeDiscovery() {
        let provider = MyCoderAutoFreeProvider()

        #expect(provider.models.isEmpty)
        #expect(provider.isReady == false)
        #expect(provider.statusMessage.isEmpty)
        #expect(provider.isModelLocked == false)
    }

    @Test("model profiles expose honest free-route characteristics")
    func modelProfiles() {
        let profile = MyCoderAutoFreeClient.profile(for: "big-pickle")
        let model = MyCoderAutoFreeClient.Model(id: "big-pickle")

        #expect(profile.displayName == "Big Pickle")
        #expect(profile.capabilities.contains("Free"))
        #expect(profile.capabilities.contains("Anonymous"))
        #expect(model.effectiveDescription.contains("OpenCode"))
        #expect(model.contextDescription == "Not reported by live catalog")
    }

    @Test("system prompt is Codable provider state")
    func systemPromptRoundTrips() throws {
        var provider = MyCoderAutoFreeProvider()
        provider.systemPrompt = "You are a precise coding assistant."
        provider.isModelLocked = true

        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(MyCoderAutoFreeProvider.self, from: data)

        #expect(decoded.systemPrompt == provider.systemPrompt)
        #expect(decoded.selectedModel == "big-pickle")
        #expect(decoded.isModelLocked)
    }
}

@Suite("MyCoderAutoFreeClient — anonymous OpenCode contract")
struct MyCoderAutoFreeClientContractTests {
    @Test("uses the official Zen base URL and OpenAI-compatible endpoint family")
    func endpointAndModelContract() {
        #expect(MyCoderAutoFreeClient.providerBaseURL.absoluteString == "https://opencode.ai/zen/v1")
        #expect(MyCoderAutoFreeProvider.defaultModelID == "big-pickle")
        #expect(MyCoderAutoFreeClient.maxConsecutiveFailures == 5)
    }

    @Test("rate limit and model errors switch immediately")
    func immediateFailoverErrors() {
        #expect(MyCoderAutoFreeClient.shouldSwitchImmediately(for: MyCoderAutoFreeError.rateLimited("429")))
        #expect(MyCoderAutoFreeClient.shouldSwitchImmediately(for: MyCoderAutoFreeError.modelUnavailable("big-pickle", "404")))
        #expect(!MyCoderAutoFreeClient.shouldSwitchImmediately(for: MyCoderAutoFreeError.apiError("HTTP 500")))
    }

    @Test("five consecutive generic failures are the switch threshold")
    func fiveFailureThreshold() {
        #expect(!MyCoderAutoFreeClient.shouldSwitch(for: MyCoderAutoFreeError.apiError("HTTP 500"), consecutiveFailures: 4))
        #expect(MyCoderAutoFreeClient.shouldSwitch(for: MyCoderAutoFreeError.apiError("HTTP 500"), consecutiveFailures: 5))
    }
}

@Suite("myCoder Auto Free conversation context")
struct MyCoderAutoFreeConversationContextTests {
    @Test("multi-turn history preserves prior finished turns and drops in-flight placeholders")
    func preservesPriorConversationTurns() {
        let history = MyCoderAutoFreeHistoryLogic.history(from: [
            .init(role: "user", content: "Remember project name", isFinished: true),
            .init(role: "assistant", content: "myCoder", isFinished: true),
            .init(role: "assistant", content: "in-flight placeholder", isFinished: false)
        ])
        #expect(history.map(\.role) == ["user", "assistant"])
        #expect(history.map(\.content) == ["Remember project name", "myCoder"])
    }
}
