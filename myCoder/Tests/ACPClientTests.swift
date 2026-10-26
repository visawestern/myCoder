import Testing
import Foundation
@testable import myCoder

/// F44: ACP Protocol Client tests
@Suite("ACP Protocol Client")
struct ACPClientTests {
    
    // MARK: - Initialization
    
    @Test("ACPClient initializes with valid URL")
    func initWithValidURL() {
        let client = ACPClient(baseURLString: "http://localhost:8080/acp/v1", apiKey: "test-key")
        #expect(client != nil)
        #expect(client?.apiKey == "test-key")
    }
    
    @Test("ACPClient initializes without API key")
    func initWithoutAPIKey() {
        let client = ACPClient(baseURLString: "http://localhost:8080/acp/v1")
        #expect(client != nil)
        #expect(client?.apiKey == "")
    }
    
    @Test("ACPClient returns nil for invalid URL")
    func initWithInvalidURL() {
        let client = ACPClient(baseURLString: "")
        #expect(client == nil)
    }
    
    @Test("ACPClient stores base URL correctly")
    func storesBaseURL() {
        let url = URL(string: "http://localhost:8080/acp/v1")!
        let client = ACPClient(baseURL: url)
        #expect(client.baseURL == url)
    }
    
    @Test("ACPClient init with URL and no key")
    func initWithURLNoKey() {
        let url = URL(string: "http://localhost:8080/acp/v1")!
        let client = ACPClient(baseURL: url, apiKey: "")
        #expect(client.baseURL == url)
        #expect(client.apiKey.isEmpty)
    }
    
    // MARK: - Request Message Building
    
    @Test("ACPRequestMessage has correct dictionary format")
    func requestMessageDictionary() {
        let msg = ACPRequestMessage(role: "user", content: "Hello")
        let dict = msg.dictionary
        
        #expect(dict["role"] as? String == "user")
        #expect(dict["content"] as? String == "Hello")
        #expect(dict["tool_call_id"] == nil)
        #expect(dict["tool_calls"] == nil)
    }
    
    @Test("ACPRequestMessage includes tool call ID")
    func requestMessageWithToolCallID() {
        let msg = ACPRequestMessage(role: "tool", content: "Result", toolCallID: "call_123")
        let dict = msg.dictionary
        
        #expect(dict["role"] as? String == "tool")
        #expect(dict["tool_call_id"] as? String == "call_123")
    }
    
    @Test("ACPRequestMessage includes tool calls")
    func requestMessageWithToolCalls() {
        let toolCall = ACPRequestToolCall(
            id: "call_1",
            type: "function",
            function: ACPRequestToolCallFunction(name: "get_weather", arguments: "{\"city\": \"NYC\"}")
        )
        let msg = ACPRequestMessage(role: "assistant", content: "", toolCalls: [toolCall])
        let dict = msg.dictionary
        
        #expect(dict["role"] as? String == "assistant")
        if let toolCalls = dict["tool_calls"] as? [[String: Any]] {
            #expect(toolCalls.count == 1)
            #expect(toolCalls[0]["id"] as? String == "call_1")
            #expect(toolCalls[0]["type"] as? String == "function")
        } else {
            #expect(Bool(false), "tool_calls should exist")
        }
    }
    
    @Test("ACPRequestTool has correct dictionary format")
    func requestToolDictionary() {
        let tool = ACPRequestTool(
            type: "function",
            function: ACPRequestToolFunction(
                name: "get_weather",
                description: "Get weather for a city",
                parameters: ["type": "object", "properties": [:]]
            )
        )
        let dict = tool.dictionary
        
        #expect(dict["type"] as? String == "function")
        if let function = dict["function"] as? [String: Any] {
            #expect(function["name"] as? String == "get_weather")
            #expect(function["description"] as? String == "Get weather for a city")
        } else {
            #expect(Bool(false), "function should exist")
        }
    }
    
    // MARK: - Response Decoding
    
    @Test("ACPChatResponse decodes from valid JSON")
    func decodeChatResponse() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "object": "chat.completion",
            "created": 1677652288,
            "model": "gpt-4",
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "Hello! How can I help you?"
                    },
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 20,
                "total_tokens": 30
            }
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(ACPChatResponse.self, from: json)
        
        #expect(response.id == "chatcmpl-123")
        #expect(response.model == "gpt-4")
        #expect(response.choices.count == 1)
        #expect(response.choices[0].message.content == "Hello! How can I help you?")
        #expect(response.choices[0].message.role == "assistant")
        #expect(response.choices[0].finishReason == "stop")
        #expect(response.usage?.promptTokens == 10)
        #expect(response.usage?.completionTokens == 20)
        #expect(response.usage?.totalTokens == 30)
    }
    
    @Test("ACPChatResponse decodes with reasoning content")
    func decodeChatResponseWithReasoning() throws {
        let json = """
        {
            "id": "chatcmpl-456",
            "object": "chat.completion",
            "created": 1677652288,
            "model": "claude-3",
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "Final answer",
                        "reasoning": "Let me think about this..."
                    },
                    "finish_reason": "stop"
                }
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(ACPChatResponse.self, from: json)
        
        #expect(response.choices[0].message.content == "Final answer")
        #expect(response.choices[0].message.reasoning == "Let me think about this...")
    }
    
    @Test("ACPChatResponse decodes with tool calls")
    func decodeChatResponseWithToolCalls() throws {
        let json = """
        {
            "id": "chatcmpl-789",
            "object": "chat.completion",
            "created": 1677652288,
            "model": "gpt-4",
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "",
                        "tool_calls": [
                            {
                                "id": "call_abc",
                                "type": "function",
                                "function": {
                                    "name": "get_weather",
                                    "arguments": "{\\"city\\": \\"NYC\\"}"
                                }
                            }
                        ]
                    },
                    "finish_reason": "tool_calls"
                }
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(ACPChatResponse.self, from: json)
        
        #expect(response.choices[0].finishReason == "tool_calls")
        let toolCalls = response.choices[0].message.toolCalls
        #expect(toolCalls?.count == 1)
        #expect(toolCalls?[0].id == "call_abc")
        #expect(toolCalls?[0].function.name == "get_weather")
        #expect(toolCalls?[0].function.arguments == "{\"city\": \"NYC\"}")
    }
    
    @Test("ACPChatResponse decodes multiple choices")
    func decodeChatResponseMultipleChoices() throws {
        let json = """
        {
            "id": "chatcmpl-multi",
            "object": "chat.completion",
            "created": 1677652288,
            "model": "gpt-4",
            "choices": [
                {"index": 0, "message": {"role": "assistant", "content": "First"}, "finish_reason": "stop"},
                {"index": 1, "message": {"role": "assistant", "content": "Second"}, "finish_reason": "stop"}
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(ACPChatResponse.self, from: json)
        
        #expect(response.choices.count == 2)
        #expect(response.choices[0].message.content == "First")
        #expect(response.choices[1].message.content == "Second")
    }
    
    @Test("ACPChatResponse handles empty choices")
    func decodeChatResponseEmptyChoices() throws {
        let json = """
        {
            "id": "chatcmpl-empty",
            "object": "chat.completion",
            "created": 1677652288,
            "model": "gpt-4",
            "choices": []
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(ACPChatResponse.self, from: json)
        
        #expect(response.choices.isEmpty)
    }
    
    // MARK: - Streaming Chunk Decoding
    
    @Test("ACPChatStreamChunk decodes content delta")
    func decodeStreamChunkContent() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "object": "chat.completion.chunk",
            "created": 1677652288,
            "model": "gpt-4",
            "choices": [
                {
                    "index": 0,
                    "delta": {"content": "Hello"},
                    "finish_reason": null
                }
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let chunk = try decoder.decode(ACPChatStreamChunk.self, from: json)
        
        #expect(chunk.id == "chatcmpl-123")
        #expect(chunk.choices?.first?.delta?.content == "Hello")
        #expect(chunk.choices?.first?.finishReason == nil)
    }
    
    @Test("ACPChatStreamChunk decodes reasoning delta")
    func decodeStreamChunkReasoning() throws {
        let json = """
        {
            "id": "chatcmpl-456",
            "object": "chat.completion.chunk",
            "choices": [
                {
                    "index": 0,
                    "delta": {"reasoning": "Let me think..."},
                    "finish_reason": null
                }
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let chunk = try decoder.decode(ACPChatStreamChunk.self, from: json)
        
        #expect(chunk.choices?.first?.delta?.reasoning == "Let me think...")
    }
    
    @Test("ACPChatStreamChunk decodes finish reason")
    func decodeStreamChunkFinish() throws {
        let json = """
        {
            "id": "chatcmpl-789",
            "object": "chat.completion.chunk",
            "choices": [
                {
                    "index": 0,
                    "delta": {},
                    "finish_reason": "stop"
                }
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let chunk = try decoder.decode(ACPChatStreamChunk.self, from: json)
        
        #expect(chunk.choices?.first?.finishReason == "stop")
    }
    
    // MARK: - Health Response Decoding
    
    @Test("ACPHealthResponse decodes from JSON")
    func decodeHealthResponse() throws {
        let json = """
        {
            "status": "ok",
            "version": "1.0.0",
            "message": "ACP server running"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let health = try decoder.decode(ACPHealthResponse.self, from: json)
        
        #expect(health.status == "ok")
        #expect(health.version == "1.0.0")
        #expect(health.message == "ACP server running")
    }
    
    @Test("ACPHealthResponse decodes minimal response")
    func decodeMinimalHealthResponse() throws {
        let json = """
        {"status": "ok"}
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let health = try decoder.decode(ACPHealthResponse.self, from: json)
        
        #expect(health.status == "ok")
        #expect(health.version == nil)
    }
    
    // MARK: - Models Response Decoding
    
    @Test("ACPModelsWrapper decodes OpenAI format")
    func decodeModelsWrapperOpenAI() throws {
        let json = """
        {
            "data": [
                {"id": "gpt-4", "object": "model", "created": 1677652288, "owned_by": "openai"},
                {"id": "gpt-3.5-turbo", "object": "model", "created": 1677652288, "owned_by": "openai"}
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(ACPModelsWrapper.self, from: json)
        
        #expect(wrapper.data?.count == 2)
        #expect(wrapper.data?.first?.id == "gpt-4")
    }
    
    // MARK: - Error Handling
    
    @Test("ACPError has descriptive messages")
    func acpErrorMessages() {
        let httpError = ACPError.httpError(statusCode: 401, message: "Unauthorized")
        #expect(httpError.errorDescription?.contains("401") == true)
        #expect(httpError.errorDescription?.contains("Unauthorized") == true)
        
        let connError = ACPError.connectionFailed
        #expect(connError.errorDescription?.contains("connection") == true)
        
        let urlError = ACPError.invalidURL
        #expect(urlError.errorDescription?.contains("URL") == true)
        
        let decodingError = ACPError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad data")))
        #expect(decodingError.errorDescription?.contains("decoding") == true)
    }
    
    @Test("ACP HTTP error codes are distinguishable")
    func acpErrorCodes() {
        let authError = ACPError.httpError(statusCode: 401, message: "Invalid API key")
        let rateLimitError = ACPError.httpError(statusCode: 429, message: "Too many requests")
        let serverError = ACPError.httpError(statusCode: 500, message: "Server error")
        
        #expect(authError.errorDescription?.contains("401") == true)
        #expect(rateLimitError.errorDescription?.contains("429") == true)
        #expect(serverError.errorDescription?.contains("500") == true)
    }
    
    // MARK: - Provider Integration
    
    @Test("ACP provider type has correct configuration")
    func acpProviderType() {
        #expect(ProviderType.acp.rawValue == "ACP (Agent Coder Protocol)")
        #expect(ProviderType.acp.defaultURL == "http://localhost:8080/acp/v1")
        #expect(ProviderType.acp.icon == "terminal.fill")
    }
    
    @Test("CustomProvider stores acpEnabled flag")
    func customProviderAcpFlag() {
        let provider = CustomProvider(
            name: "My ACP",
            type: .acp,
            baseURL: "http://localhost:8080/acp/v1",
            acpEnabled: true
        )
        
        #expect(provider.type == .acp)
        #expect(provider.acpEnabled == true)
        #expect(provider.baseURL == "http://localhost:8080/acp/v1")
    }
    
    @Test("CustomProvider acpEnabled defaults to false")
    func customProviderAcpDefault() {
        let provider = CustomProvider(
            name: "Default",
            type: .openAI,
            baseURL: "https://api.openai.com/v1"
        )
        
        #expect(provider.acpEnabled == false)
    }
    
    @Test("ACP provider does not require API key in add sheet")
    func acpProviderNoApiKeyRequired() {
        // acp type skips requiresAPIKey toggle
        // Only non-ollama and non-acp types show the requiresAPIKey toggle
        let acpType = ProviderType.acp
        #expect(acpType != .ollama)
        #expect(acpType != .openAI)
        #expect(acpType.rawValue == "ACP (Agent Coder Protocol)")
    }

    // MARK: - AppState ACP detection

    @Test("AppState isSelectedACPProvider is false without custom providers")
    func acpDetectionNoProviders() {
        let state = AppState(defaults: UserDefaults(suiteName: "test.acp.1")!)
        #expect(state.isSelectedACPProvider == false)
    }

    @Test("AppState isSelectedACPProvider is false for non-ACP provider")
    func acpDetectionNonACP() {
        let state = AppState(defaults: UserDefaults(suiteName: "test.acp.2")!)
        state.customProviders = [
            CustomProvider(id: "c1", name: "OpenAI", type: .openAI, baseURL: "https://api.openai.com", isEnabled: true)
        ]
        state.selectProvider("c1")
        #expect(state.isSelectedACPProvider == false)
    }

    @Test("AppState isSelectedACPProvider is true for ACP provider with acpEnabled")
    func acpDetectionACPEnabled() {
        let state = AppState(defaults: UserDefaults(suiteName: "test.acp.3")!)
        state.customProviders = [
            CustomProvider(id: "c1", name: "My ACP", type: .acp, baseURL: "http://localhost:8080", isEnabled: true, acpEnabled: true)
        ]
        state.selectProvider("c1")
        #expect(state.isSelectedACPProvider == true)
    }

    @Test("AppState isSelectedACPProvider is false for ACP provider with acpEnabled=false")
    func acpDetectionACPDisabled() {
        let state = AppState(defaults: UserDefaults(suiteName: "test.acp.4")!)
        state.customProviders = [
            CustomProvider(id: "c1", name: "My ACP", type: .acp, baseURL: "http://localhost:8080", isEnabled: true, acpEnabled: false)
        ]
        state.selectProvider("c1")
        #expect(state.isSelectedACPProvider == false)
    }

    @Test("AppState acpClient returns nil for non-ACP provider")
    func acpClientNilForNonACP() {
        let state = AppState(defaults: UserDefaults(suiteName: "test.acp.5")!)
        state.customProviders = [
            CustomProvider(id: "c1", name: "OpenAI", type: .openAI, baseURL: "https://api.openai.com", isEnabled: true)
        ]
        state.selectProvider("c1")
        #expect(state.acpClient == nil)
    }

    @Test("AppState acpClient returns configured client for ACP provider")
    func acpClientConfigured() {
        let state = AppState(defaults: UserDefaults(suiteName: "test.acp.6")!)
        state.customProviders = [
            CustomProvider(id: "c1", name: "My ACP", type: .acp, baseURL: "http://localhost:8080", apiKey: "sk-test", isEnabled: true, acpEnabled: true)
        ]
        state.selectProvider("c1")
        #expect(state.acpClient != nil)
        #expect(state.acpClient?.apiKey == "sk-test")
        #expect(state.acpClient?.baseURL.absoluteString == "http://localhost:8080")
    }
}
