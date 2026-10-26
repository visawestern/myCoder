import Foundation

/// ACP message types extracted to a Foundation-only file so they are unit-testable
/// without pulling in the full ACPClient (which uses URLSession async APIs not
/// available on Linux). See plan Раздел 9 Блок 2.

/// A single part of a multimodal ACP message content (OpenAI-compatible).
/// Plan Раздел 9 Блок 2 п.12 — ACP must send real image bytes, not a placeholder.
enum ACPContentPart: Equatable {
    case text(String)
    case imageURL(url: String)   // data URL or remote URL

    var dictionary: [String: Any] {
        switch self {
        case .text(let text):
            return ["type": "text", "text": text]
        case .imageURL(let url):
            return ["type": "image_url", "image_url": ["url": url]]
        }
    }
}

struct ACPRequestToolCallFunction {
    let name: String
    let arguments: String

    var dictionary: [String: Any] {
        ["name": name, "arguments": arguments]
    }
}

struct ACPRequestToolCall {
    let id: String
    let type: String
    let function: ACPRequestToolCallFunction

    var dictionary: [String: Any] {
        ["id": id, "type": type, "function": function.dictionary]
    }
}

struct ACPRequestMessage {
    let role: String
    let content: String
    let toolCallID: String?
    let toolCalls: [ACPRequestToolCall]?
    /// Multimodal content parts (text + images). When present, the serialized
    /// `content` is an array of parts instead of a plain string (plan Блок 2 п.12).
    let contentParts: [ACPContentPart]?

    init(role: String, content: String, toolCallID: String? = nil, toolCalls: [ACPRequestToolCall]? = nil, contentParts: [ACPContentPart]? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.contentParts = contentParts
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = ["role": role]
        if let parts = contentParts, !parts.isEmpty {
            d["content"] = parts.map { $0.dictionary }
        } else {
            d["content"] = content
        }
        if let toolCallID {
            d["tool_call_id"] = toolCallID
        }
        if let toolCalls {
            d["tool_calls"] = toolCalls.map { $0.dictionary }
        }
        return d
    }
}

struct ACPRequestTool {
    let type: String
    let function: ACPRequestToolFunction

    var dictionary: [String: Any] {
        ["type": type, "function": function.dictionary]
    }
}

struct ACPRequestToolFunction {
    let name: String
    let description: String
    let parameters: [String: Any]

    var dictionary: [String: Any] {
        ["name": name, "description": description, "parameters": parameters]
    }
}

/// Builds ACP chat-completion request bodies. Extracted to a Foundation-only
/// file so the body contract is unit-testable without URLSession (E06: call
/// parameters temperature/max_tokens/top_p must actually reach the model on
/// the ACP path — plan Раздел 9 п.49, they used to be silently dropped).
enum ACPRequestBodyBuilder {
    static func body(
        model: String,
        messages: [ACPRequestMessage],
        agent: String = "build",
        variant: String? = nil,
        tools: [ACPRequestTool]? = nil,
        apiKey: String = "",
        parameters: ModelCallParameters = ModelCallParameters()
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { $0.dictionary },
            "stream": false,
            "agent": agent
        ]
        merge(into: &body, variant: variant, tools: tools, apiKey: apiKey, parameters: parameters)
        return body
    }

    static func streamBody(
        model: String,
        messages: [ACPRequestMessage],
        agent: String = "build",
        variant: String? = nil,
        tools: [ACPRequestTool]? = nil,
        apiKey: String = "",
        parameters: ModelCallParameters = ModelCallParameters()
    ) -> [String: Any] {
        var body = body(
            model: model, messages: messages, agent: agent, variant: variant,
            tools: tools, apiKey: apiKey, parameters: parameters
        )
        body["stream"] = true
        return body
    }

    private static func merge(
        into body: inout [String: Any],
        variant: String?,
        tools: [ACPRequestTool]?,
        apiKey: String,
        parameters: ModelCallParameters
    ) {
        if let variant {
            body["variant"] = variant
        }
        if let tools, !tools.isEmpty {
            body["tools"] = tools.map { $0.dictionary }
        }
        if !apiKey.isEmpty {
            body["apiKey"] = apiKey
        }
        for (key, value) in ModelCallParametersStore.requestFragment(parameters) {
            body[key] = value
        }
    }
}
