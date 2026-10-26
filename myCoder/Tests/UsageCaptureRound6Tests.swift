import Testing
import Foundation
@testable import myCoder

/// In-memory transport for deterministic testing of DirectChatClient.
struct MockDirectChatTransport: DirectChatTransport {
    var response: (Int, Data)?
    func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? {
        response
    }
    func get(url: String, headers: [String: String]) async -> (Int, Data)? { nil }
}

@Suite("DirectChatClient usage extraction (round 6)")
struct DirectChatRound6Tests {

    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    @Test func sendReturnsUsageFromOpenAIResponse() async throws {
        let body = json("""
        {"id":"x","object":"chat.completion","created":1,"model":"gpt-4o",
         "choices":[{"index":0,"message":{"role":"assistant","content":"hello"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":200,"completion_tokens":75,"total_tokens":275,"cost_usd":0.03}}
        """)
        let transport = MockDirectChatTransport(response: (200, body))
        let result = try await DirectChatClient.send(
            baseURL: "http://x/", apiKey: nil, model: "gpt-4o",
            messages: [DirectChatMessage(role: "user", content: "hi")],
            transport: transport)
        #expect(result.content == "hello")
        let usage = try #require(result.usage)
        #expect(usage.promptTokens == 200)
        #expect(usage.completionTokens == 75)
        #expect(usage.costUSD == 0.03)
        #expect(usage.modelID == "gpt-4o")
    }

    @Test func sendReturnsNilUsageWhenProviderOmitsIt() async throws {
        let body = json("""
        {"id":"x","object":"chat.completion","created":1,"model":"qwen",
         "choices":[{"index":0,"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}]}
        """)
        let transport = MockDirectChatTransport(response: (200, body))
        let result = try await DirectChatClient.send(
            baseURL: "http://x/", apiKey: nil, model: "qwen",
            messages: [DirectChatMessage(role: "user", content: "hi")],
            transport: transport)
        #expect(result.content == "hi")
        #expect(result.usage == nil)
    }

    @Test func sendHandlesStringEncodedTokens() async throws {
        let body = json("""
        {"id":"x","object":"chat.completion","created":1,"model":"m",
         "choices":[{"index":0,"message":{"role":"assistant","content":"a"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":"150","completion_tokens":"50"}}
        """)
        let transport = MockDirectChatTransport(response: (200, body))
        let result = try await DirectChatClient.send(
            baseURL: "http://x/", apiKey: nil, model: "m",
            messages: [DirectChatMessage(role: "user", content: "hi")],
            transport: transport)
        let usage = try #require(result.usage)
        #expect(usage.promptTokens == 150)
        #expect(usage.completionTokens == 50)
    }

    @Test func sendParsesOllamaStyleResponse() async throws {
        let body = json("""
        {"model":"llama","message":{"role":"assistant","content":"yo"},"done":true,
         "prompt_eval_count":80,"eval_count":40}
        """)
        let transport = MockDirectChatTransport(response: (200, body))
        let result = try await DirectChatClient.send(
            baseURL: "http://x/", apiKey: nil, model: "llama",
            messages: [DirectChatMessage(role: "user", content: "hi")],
            transport: transport)
        #expect(result.content == "yo")
        // Ollama exposes no usage block → usage nil (content still parsed).
        #expect(result.usage == nil)
    }
}
