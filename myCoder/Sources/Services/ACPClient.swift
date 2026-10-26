import Foundation

// MARK: - ACP Protocol Client

/// Agent Coder Protocol (ACP) client for communicating with ACP-compatible agent servers.
/// ACP extends the OpenAI-compatible chat API with agent-specific capabilities:
/// - Agent mode (build/plan/compose)
/// - Tool calling
/// - Streaming via SSE
/// - Session management
final class ACPClient {
    let baseURL: URL
    let apiKey: String
    
    private let session: URLSession
    private let decoder: JSONDecoder
    
    init(baseURL: URL, apiKey: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }
    
    convenience init?(baseURLString: String, apiKey: String = "") {
        guard let url = URL(string: baseURLString) else { return nil }
        self.init(baseURL: url, apiKey: apiKey)
    }
    
    // MARK: - Chat Completions
    
    /// Sends a chat completion request to the ACP server
    func sendChatCompletion(
        messages: [ACPRequestMessage],
        model: String,
        agent: String = "build",
        variant: String? = nil,
        tools: [ACPRequestTool]? = nil,
        parameters: ModelCallParameters = ModelCallParameters(),
        stream: Bool = false
    ) async throws -> ACPChatResponse {
        var body = ACPRequestBodyBuilder.body(
            model: model, messages: messages, agent: agent, variant: variant,
            tools: tools, apiKey: apiKey, parameters: parameters
        )
        body["stream"] = stream
        
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ACPError.httpError(statusCode: code, message: errorBody)
        }
        
        return try decoder.decode(ACPChatResponse.self, from: data)
    }
    
    // MARK: - Streaming Chat Completions
    
    /// Sends a streaming chat completion request via SSE
    func streamChatCompletion(
        messages: [ACPRequestMessage],
        model: String,
        agent: String = "build",
        variant: String? = nil,
        tools: [ACPRequestTool]? = nil,
        parameters: ModelCallParameters = ModelCallParameters(),
        onEvent: @escaping (ACPStreamEvent) -> Void
    ) async throws {
        let body = ACPRequestBodyBuilder.streamBody(
            model: model, messages: messages, agent: agent, variant: variant,
            tools: tools, apiKey: apiKey, parameters: parameters
        )
        
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ACPError.httpError(statusCode: code, message: "Stream connection failed")
        }
        
        var currentEvent = ""
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let data = String(line.dropFirst(6))
                if data == "[DONE]" {
                    onEvent(.done)
                    return
                }
                currentEvent = data
            } else if line.isEmpty && !currentEvent.isEmpty {
                // End of SSE event block — parse it
                if let jsonData = currentEvent.data(using: .utf8),
                   let chunk = try? decoder.decode(ACPChatStreamChunk.self, from: jsonData) {
                    if let choice = chunk.choices?.first {
                        if let delta = choice.delta {
                            if let content = delta.content {
                                onEvent(.content(content))
                            }
                            if let reasoning = delta.reasoning {
                                onEvent(.reasoning(reasoning))
                            }
                            if let toolCalls = delta.toolCalls {
                                onEvent(.toolCalls(toolCalls))
                            }
                        }
                        if choice.finishReason != nil {
                            onEvent(.finish(choice.finishReason ?? ""))
                        }
                    }
                }
                currentEvent = ""
            }
        }
    }
    
    // MARK: - Health Check
    
    /// Checks if the ACP server is reachable
    func health() async throws -> ACPHealthResponse {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ACPError.connectionFailed
        }
        
        return try decoder.decode(ACPHealthResponse.self, from: data)
    }
    
    // MARK: - Models
    
    /// Lists available models from the ACP server
    func listModels() async throws -> [ACPModel] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ACPError.connectionFailed
        }
        
        let wrapper = try decoder.decode(ACPModelsWrapper.self, from: data)
        return wrapper.data ?? wrapper.models ?? []
    }
}

// MARK: - Request Models

// ACPContentPart, ACPRequestMessage, ACPRequestToolCall, ACPRequestToolCallFunction,
// ACPRequestTool, ACPRequestToolFunction and ACPRequestBodyBuilder moved to
// ACPMessageTypes.swift (Foundation-only, unit-testable).

// MARK: - Response Models

struct ACPChatResponse: Codable {
    let id: String
    let object: String
    let created: Int64
    let model: String
    let choices: [ACPChoice]
    let usage: ACPUsage?
}

struct ACPChoice: Codable {
    let index: Int
    let message: ACPResponseMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

struct ACPResponseMessage: Codable {
    let role: String
    let content: String?
    let reasoning: String?
    let toolCalls: [ACPResponseToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role, content, reasoning
        case toolCalls = "tool_calls"
    }
}

struct ACPResponseToolCall: Codable {
    let id: String
    let type: String
    let function: ACPResponseToolCallFunction
}

struct ACPResponseToolCallFunction: Codable {
    let name: String
    let arguments: String
}

struct ACPUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Streaming Models

struct ACPChatStreamChunk: Codable {
    let id: String?
    let object: String?
    let created: Int64?
    let model: String?
    let choices: [ACPStreamChoice]?
}

struct ACPStreamChoice: Codable {
    let index: Int?
    let delta: ACPStreamDelta?
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

struct ACPStreamDelta: Codable {
    let role: String?
    let content: String?
    let reasoning: String?
    let toolCalls: [ACPResponseToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role, content, reasoning
        case toolCalls = "tool_calls"
    }
}

// MARK: - Stream Events

enum ACPStreamEvent {
    case content(String)
    case reasoning(String)
    case toolCalls([ACPResponseToolCall])
    case finish(String)
    case done
}

// MARK: - Health & Models

struct ACPHealthResponse: Codable {
    let status: String
    let version: String?
    let message: String?
}

struct ACPModelsWrapper: Codable {
    let data: [ACPModel]?
    let models: [ACPModel]?  // Fallback for non-OpenAI format
}

struct ACPModel: Codable {
    let id: String
    let object: String?
    let created: Int64?
    let ownedBy: String?
    
    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}

// MARK: - ACP Error

enum ACPError: Error, LocalizedError {
    case httpError(statusCode: Int, message: String)
    case connectionFailed
    case invalidURL
    case decodingError(Error)
    case emptyResponse
    
    var errorDescription: String? {
        switch self {
        case .httpError(let code, let message):
            return "ACP HTTP error \(code): \(message)"
        case .connectionFailed:
            return "ACP connection failed"
        case .invalidURL:
            return "Invalid ACP server URL"
        case .decodingError(let error):
            return "ACP decoding error: \(error.localizedDescription)"
        case .emptyResponse:
            return "The ACP provider returned an empty response. Check the selected model and retry."
        }
    }
}
