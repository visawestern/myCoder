import Testing
import Foundation
@testable import myCoder

@Suite("Send routing + direct chat client (empty-response fix)")
struct SendRoutingTests {

    // MARK: - SendRouteResolver

    @Test func autoFreeRoutesToOpenCodeZen() {
        let route = SendRouteResolver.route(
            selectedProviderID: MyCoderAutoFreeProvider.builtInID,
            selectedModel: MyCoderAutoFreeProvider.defaultModelID,
            serverConnected: false,
            isACP: false,
            customProviders: [],
            localProviders: [],
            webProviderIDs: []
        )
        #expect(route == .autoFree)
        #expect(!SendRouteResolver.requiresServer(route))
    }

    @Test func everySupportedWebProviderUsesBrowserRoute() {
        for id in ["kimi", "qwen", "chatgpt"] {
            let route = SendRouteResolver.route(
                selectedProviderID: "web:\(id)", selectedModel: "live-model",
                serverConnected: false, isACP: false,
                customProviders: [], localProviders: [], webProviderIDs: [id]
            )
            #expect(route == .web(configID: id))
            #expect(!SendRouteResolver.requiresServer(route))
        }
    }

    @Test func everySupportedWebProviderPassesReadinessWithoutServe() {
        for id in ["kimi", "qwen", "chatgpt"] {
            #expect(SendReadinessLogic.connectionValidationError(
                serverConnected: false,
                selectedProviderID: "web:\(id)",
                webProviderIDs: [id]
            ) == nil)
        }
    }

    @Test func webProviderRoutesToWeb() {
        let route = SendRouteResolver.route(
            selectedProviderID: "web:abc", selectedModel: "k2",
            serverConnected: false, isACP: false,
            customProviders: [], localProviders: [], webProviderIDs: ["abc"]
        )
        #expect(route == .web(configID: "abc"))
    }

    @Test func localOllamaRoutesToOpenAICompatibleV1() {
        let ollama = LocalProviderConfig(kind: .ollama, host: "127.0.0.1", port: 11434)
        let route = SendRouteResolver.route(
            selectedProviderID: ollama.id, selectedModel: "llama3",
            serverConnected: false, isACP: false,
            customProviders: [], localProviders: [ollama], webProviderIDs: []
        )
        #expect(route == .openAICompatible(baseURL: "http://127.0.0.1:11434/v1", apiKey: nil, model: "llama3"))
    }

    @Test func openCodeLocalRoutesToServeSessionAPI() {
        // A real `opencode serve` speaks the session REST API, not OpenAI /v1
        // (verified live against 1.18.29) — route it to the session client.
        let oc = LocalProviderConfig(kind: .openCode, host: "127.0.0.1", port: 4096)
        let route = SendRouteResolver.route(
            selectedProviderID: oc.id, selectedModel: "big-pickle",
            serverConnected: false, isACP: false,
            customProviders: [], localProviders: [oc], webProviderIDs: []
        )
        #expect(route == .openCodeServe(baseURL: "http://127.0.0.1:4096", headers: [:], providerID: "opencode", model: "big-pickle"))
    }

    @Test func mimoCLILocalUsesServeBaseNoV1() {
        let cli = LocalProviderConfig(kind: .localAgent, host: "127.0.0.1", port: 4096)
        let route = SendRouteResolver.route(
            selectedProviderID: cli.id, selectedModel: "m",
            serverConnected: false, isACP: false,
            customProviders: [], localProviders: [cli], webProviderIDs: []
        )
        #expect(route == .openAICompatible(baseURL: "http://127.0.0.1:4096", apiKey: nil, model: "m"))
    }

    @Test func customProviderRoutesToOpenAICompatible() {
        let custom = CustomProvider(id: "c1", name: "My", type: .openAI,
                                    baseURL: "https://api.x.ai/v1", apiKey: "k", models: ["m"])
        let route = SendRouteResolver.route(
            selectedProviderID: "c1", selectedModel: "m",
            serverConnected: false, isACP: false,
            customProviders: [custom], localProviders: [], webProviderIDs: []
        )
        #expect(route == .openAICompatible(baseURL: "https://api.x.ai/v1", apiKey: "k", model: "m"))
    }

    // MARK: - Audit ARCH-04: the key must resolve even when the in-memory
    // copy was stripped because it lives in the Keychain.

    @Test func customProviderWithKeychainOnlyKeyStillRoutesWithKey() {
        // In-memory copy has apiKey stripped (post-Keychain-migration state),
        // but the Keychain holds the real key under the provider id.
        DatabaseBridge.shared.saveProviderAPIKey(providerId: "kc1", apiKey: "keychain-key")
        defer { DatabaseBridge.shared.deleteProviderAPIKey(providerId: "kc1") }
        let stripped = CustomProvider(id: "kc1", name: "KC", type: .openAI,
                                      baseURL: "https://api.x.ai/v1", apiKey: "", models: ["m"])
        let route = SendRouteResolver.route(
            selectedProviderID: "kc1", selectedModel: "m",
            serverConnected: false, isACP: false,
            customProviders: [stripped], localProviders: [], webProviderIDs: []
        )
        guard case .openAICompatible(_, let apiKey, _) = route else {
            Issue.record("Expected openAICompatible route, got \(route)")
            return
        }
        #expect(apiKey == "keychain-key",
                "A provider whose key lives only in the Keychain must still route with it")
    }

    @Test func acpTakesPriorityWhenFlagged() {
        let route = SendRouteResolver.route(
            selectedProviderID: "acp1", selectedModel: "m",
            serverConnected: false, isACP: true,
            customProviders: [], localProviders: [], webProviderIDs: []
        )
        #expect(route == .acp)
    }

    @Test func serverConnectedFallsBackToMimoServe() {
        let route = SendRouteResolver.route(
            selectedProviderID: "srv", selectedModel: "m",
            serverConnected: true, isACP: false,
            customProviders: [], localProviders: [], webProviderIDs: []
        )
        #expect(route == .mimoServe)
    }

    @Test func nothingSelectedIsNone() {
        let route = SendRouteResolver.route(
            selectedProviderID: "", selectedModel: "", serverConnected: false, isACP: false,
            customProviders: [], localProviders: [], webProviderIDs: []
        )
        #expect(route == .none)
        #expect(!SendRouteResolver.requiresServer(.none))
        #expect(SendRouteResolver.requiresServer(.mimoServe))
    }

    // MARK: - DirectChatClient body + parsing

    @Test func requestBodyIncludesModelAndMessages() {
        let body = DirectChatClient.requestBody(
            model: "gpt-4o",
            messages: [DirectChatMessage(role: "user", content: "hi")]
        )
        #expect(body["model"] as? String == "gpt-4o")
        let msgs = body["messages"] as? [[String: Any]]
        #expect(msgs?.first?["role"] as? String == "user")
        #expect(msgs?.first?["content"] as? String == "hi")
    }

    @Test func requestBodyIncludesCustomParams() {
        let body = DirectChatClient.requestBody(
            model: "m", messages: [], parameters: ModelCallParameters(temperature: 0.3, maxTokens: 512)
        )
        #expect(body["temperature"] as? Double == 0.3)
        #expect(body["max_tokens"] as? Int == 512)
    }

    @Test func parsesOpenAIResponse() {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"hello"}}]}"#.utf8)
        #expect(DirectChatClient.parseResponseText(data) == "hello")
    }

    @Test func parsesOllamaResponse() {
        let data = Data(#"{"message":{"role":"assistant","content":"hi there"}}"#.utf8)
        #expect(DirectChatClient.parseResponseText(data) == "hi there")
    }

    @Test func messagesComposeSystemAndUser() {
        let msgs = DirectChatClient.messages(systemPrompt: "be brief", userText: "hello")
        #expect(msgs.count == 2)
        #expect(msgs[0].role == "system")
        #expect(msgs[1].role == "user")
    }

    // MARK: - DirectChatClient send (scripted transport, no network)

    private struct ScriptedTransport: DirectChatTransport {
        let status: Int
        let body: Data
        func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? { (status, self.body) }
        func get(url: String, headers: [String: String]) async -> (Int, Data)? { nil }
    }

    @Test func sendReturnsAssistantText() async throws {
        let t = ScriptedTransport(status: 200, body: Data(#"{"choices":[{"message":{"content":"answer"}}]}"#.utf8))
        let result = try await DirectChatClient.send(
            baseURL: "http://localhost:11434/v1", apiKey: nil, model: "m",
            messages: [DirectChatMessage(role: "user", content: "q")], transport: t
        )
        #expect(result.content == "answer")
        #expect(result.usage == nil)
    }

    @Test func sendThrowsOnHTTPError() async {
        let t = ScriptedTransport(status: 500, body: Data("boom".utf8))
        await #expect(throws: DirectChatError.self) {
            try await DirectChatClient.send(
                baseURL: "http://x/v1", apiKey: nil, model: "m",
                messages: [], transport: t
            )
        }
    }

    // Audit P5: errors must produce useful user-facing text (not generic).
    @Test func errorDescriptionsAreInformative() {
        #expect(DirectChatError.http(status: 500, body: "boom").errorDescription?.contains("500") == true)
        #expect(DirectChatError.http(status: 500, body: "boom").errorDescription?.contains("boom") == true)
        #expect(DirectChatError.transport("refused").errorDescription?.contains("refused") == true)
        #expect(DirectChatError.decode.errorDescription?.isEmpty == false)
    }
}
