import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Result of a direct (OpenAI-compatible) chat call. `usage` is nil when the
/// provider did not return token accounting (e.g. local Ollama without usage).
/// `reasoning` carries the provider's thinking channel when it sends one
/// separately from the answer (`reasoning_content`, `reasoning`, `thinking`);
/// without it the UI had nothing to render and the spoiler stayed empty.
struct DirectChatResult: Equatable {
    let content: String
    let reasoning: String?
    let usage: UsageCapture?

    init(content: String, reasoning: String? = nil, usage: UsageCapture? = nil) {
        self.content = content
        self.reasoning = reasoning
        self.usage = usage
    }
}

/// Real OpenAI-compatible chat client for local (Ollama/OpenCode) and custom
/// providers so messages actually reach the selected model (fixes the empty-
/// response bug for non-serve providers). Body building is pure/testable; the
/// HTTP send uses an injectable transport.
struct DirectChatMessage: Equatable {
    let role: String   // "user" | "assistant" | "system"
    let content: String

    /// E01 (Раздел 9 п.10(c)): optional OpenAI-style multimodal parts
    /// (`[{"type":"text",...},{"type":"image_url","image_url":{"url":dataURL}}]`).
    /// When present, `content` is serialized as an array so images/files
    /// actually reach Ollama/OpenCode/Local Agent/custom providers instead of
    /// being silently dropped. nil keeps the old plain-string contract.
    let parts: [[String: Any]]?

    init(role: String, content: String, parts: [[String: Any]]? = nil) {
        self.role = role
        self.content = content
        self.parts = parts
    }

    /// Equality compares role + text; parts are attachment metadata and are
    /// intentionally not part of message identity (they don't survive as
    /// comparable JSON dictionaries).
    static func == (lhs: DirectChatMessage, rhs: DirectChatMessage) -> Bool {
        lhs.role == rhs.role && lhs.content == rhs.content
    }

    /// What the body's `content` field should be: the parts array when the
    /// message carries attachments, otherwise the plain text string (keeps
    /// backward compatibility for text-only conversations).
    func serializedContent() -> Any {
        if let parts, !parts.isEmpty {
            return parts
        }
        return content
    }

    /// Build the OpenAI-compatible image parts for a clipboard image
    /// (reuses the data-URL convention; same contract as the ACP path).
    static func imageParts(for image: ClipboardImage) -> [[String: Any]] {
        guard !image.base64.isEmpty else { return [] }
        return [
            [
                "type": "image_url",
                "image_url": ["url": MessagePartsBuilder.dataURL(mimeType: image.mimeType, base64: image.base64)]
            ]
        ]
    }
}

protocol DirectChatTransport {
    /// POST JSON to url, return (status, body) or nil on failure.
    func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)?
    /// GET url, return (status, body) or nil on failure.
    func get(url: String, headers: [String: String]) async -> (Int, Data)?
}

enum DirectChatClient {
    /// Build an OpenAI /chat/completions request body. Includes per-model call
    /// parameters (temperature/max_tokens/...) when customized (Раздел 13 п.14).
    static func requestBody(model: String,
                           messages: [DirectChatMessage],
                           parameters: ModelCallParameters = ModelCallParameters(),
                           stream: Bool = false) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.serializedContent()] },
            "stream": stream
        ]
        for (k, v) in ModelCallParametersStore.requestFragment(parameters) {
            // OpenAI uses "system" as a message, not a body key — skip here.
            if k == "system" { continue }
            body[k] = v
        }
        return body
    }

    /// Extract assistant text from an OpenAI-compatible response body.
    /// Kept for any caller that only needs the text; usage-aware callers should
    /// use `parseResponse`.
    static func parseResponseText(_ data: Data) -> String? {
        parseResponse(data)?.content
    }

    /// Parse a full OpenAI/Ollama response into text + optional usage. Usage is
    /// extracted from the top-level `usage` block (OpenAI) when present.
    /// `contextBytes` (harness-tax C1) is the outgoing initial-context size
    /// the caller already sent; it rides along on the capture for aggregation.
    static func parseResponse(_ data: Data, contextBytes: Int = 0) -> DirectChatResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var content: String?
        var reasoning: String?
        // OpenAI: choices[0].message.content
        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any] {
            content = message["content"] as? String
            reasoning = reasoningText(in: message)
        }
        // Ollama /api/chat style: message.content (thinking arrives as
        // `message.thinking` on reasoning models).
        if content == nil, let message = json["message"] as? [String: Any] {
            content = message["content"] as? String
            if reasoning == nil { reasoning = reasoningText(in: message) }
        }
        // A few gateways put the thinking channel at the top level.
        if reasoning == nil { reasoning = reasoningText(in: json) }
        guard let content,
              ProviderResponseValidationLogic.hasVisibleContent(content) else { return nil }

        let usage = Self.extractUsage(from: json, contextBytes: contextBytes)
        return DirectChatResult(
            content: content,
            reasoning: normalizedReasoning(reasoning),
            usage: usage
        )
    }

    /// Providers spell the thinking channel differently and some wrap it in an
    /// array of `{type, text}` blocks. Read every known spelling; unknown
    /// shapes are ignored rather than crashing the whole response.
    static func reasoningText(in container: [String: Any]) -> String? {
        for key in ["reasoning_content", "reasoning", "thinking"] {
            if let text = reasoningValue(container[key]), !text.isEmpty { return text }
        }
        return nil
    }

    private static func reasoningValue(_ raw: Any?) -> String? {
        if let text = raw as? String { return text }
        if let dict = raw as? [String: Any] {
            for key in ["text", "content", "summary"] {
                if let text = dict[key] as? String, !text.isEmpty { return text }
            }
            return nil
        }
        if let array = raw as? [Any] {
            var chunks: [String] = []
            for item in array {
                guard let text = reasoningValue(item), !text.isEmpty else { continue }
                if !chunks.contains(text) { chunks.append(text) }
            }
            return chunks.isEmpty ? nil : chunks.joined(separator: "\n\n")
        }
        return nil
    }

    private static func normalizedReasoning(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Merge reasoning blocks across agent-loop iterations. Some gateways
    /// repeat an earlier block verbatim; a repeated block is not a second
    /// thought and must not be shown twice.
    static func mergedReasoning(_ chunks: [String]) -> String? {
        var merged: [String] = []
        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, merged.last != trimmed else { continue }
            merged.append(trimmed)
        }
        return merged.isEmpty ? nil : merged.joined(separator: "\n\n")
    }

    /// Read the top-level `usage` block. Tolerant of missing/partial fields and
    /// string-encoded numbers some gateways emit.
    private static func responseContainsBlankAssistantContent(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return !ProviderResponseValidationLogic.hasVisibleContent(content)
        }
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? String {
            return !ProviderResponseValidationLogic.hasVisibleContent(content)
        }
        return false
    }

    /// Usage block from a response or a stream chunk. Internal so the
    /// streaming client can read the final `usage` event of an SSE stream.
    static func usage(from json: [String: Any], contextBytes: Int = 0) -> UsageCapture? {
        extractUsage(from: json, contextBytes: contextBytes)
    }

    private static func extractUsage(from json: [String: Any], contextBytes: Int = 0) -> UsageCapture? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let prompt = intValue(usage["prompt_tokens"])
        let completion = intValue(usage["completion_tokens"])
        let cost = doubleValue(usage["cost_usd"]) ?? doubleValue(usage["cost"])
        let model = stringValue(json["model"])
        let provider = stringValue(usage["provider_id"])
        // Skip a usage block that carried no token accounting at all.
        guard prompt > 0 || completion > 0 else { return nil }
        return UsageCapture(promptTokens: prompt, completionTokens: completion,
                            costUSD: cost, modelID: model, providerID: provider.isEmpty ? "direct" : provider,
                            contextBytes: contextBytes)
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let n = raw as? Int { return n }
        if let n = raw as? Int64 { return Int(n) }
        if let n = raw as? Double { return Int(n) }
        if let s = raw as? String, let n = Int(s) { return n }
        return 0
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let n = raw as? Double { return n }
        if let n = raw as? Int { return Double(n) }
        if let s = raw as? String, let n = Double(s) { return n }
        return nil
    }

    private static func stringValue(_ raw: Any?) -> String {
        if let s = raw as? String { return s }
        return ""
    }

    /// Compose the full message list including an optional system prompt.
    static func messages(systemPrompt: String?, userText: String,
                        history: [DirectChatMessage] = []) -> [DirectChatMessage] {
        var msgs: [DirectChatMessage] = []
        if let sys = systemPrompt, !sys.isEmpty { msgs.append(DirectChatMessage(role: "system", content: sys)) }
        msgs.append(contentsOf: history)
        msgs.append(DirectChatMessage(role: "user", content: userText))
        return msgs
    }

    /// Send a chat completion and return the assistant text plus any usage the
    /// provider reported, or throws.
    static func send(baseURL: String,
                    apiKey: String?,
                    model: String,
                    messages: [DirectChatMessage],
                    parameters: ModelCallParameters = ModelCallParameters(),
                    transport: DirectChatTransport = URLSessionDirectChatTransport()) async throws -> DirectChatResult {
        let url = baseURL.hasSuffix("/") ? "\(baseURL)chat/completions" : "\(baseURL)/chat/completions"
        var headers = ["Content-Type": "application/json"]
        if let key = apiKey, !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
        let body = requestBody(model: model, messages: messages, parameters: parameters)
        let data = try JSONSerialization.data(withJSONObject: body)
        guard let (status, respData) = await transport.post(url: url, headers: headers, body: data) else {
            throw DirectChatError.transport("No response from \(url)")
        }
        guard (200..<300).contains(status) else {
            let text = String(data: respData, encoding: .utf8) ?? ""
            throw DirectChatError.http(status: status, body: text)
        }
        // Harness-tax C1: initial-context size actually sent (text only).
        let contextBytes = messages.reduce(0) { $0 + $1.content.utf8.count }
        guard let result = parseResponse(respData, contextBytes: contextBytes) else {
            if Self.responseContainsBlankAssistantContent(respData) {
                throw DirectChatError.emptyResponse
            }
            throw DirectChatError.decode
        }
        return result
    }
}

enum DirectChatError: Error, Equatable, LocalizedError {
    case transport(String)
    case http(status: Int, body: String)
    case decode
    case emptyResponse

    /// User-facing message shown in the chat when a direct send fails
    /// (audit P5 — generic localizedDescription was useless).
    var errorDescription: String? {
        switch self {
        case .transport(let msg):
            return "Could not reach the provider: \(msg). Check the address/port and that the server is running."
        case .http(let status, let body):
            let detail = body.isEmpty ? "" : " — \(body.prefix(200))"
            return "Provider returned HTTP \(status)\(detail)"
        case .decode:
            return "The provider's response could not be parsed (unexpected format)."
        case .emptyResponse:
            return "The provider returned an empty response. Check the selected model and retry."
        }
    }
}

/// Live transport over URLSession (cross-platform continuation bridge).
struct URLSessionDirectChatTransport: DirectChatTransport {
    let session: URLSession
    init(timeout: TimeInterval = 120) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        self.session = URLSession(configuration: cfg)
    }
    func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return await withCheckedContinuation { cont in
            session.dataTask(with: req) { data, response, _ in
                guard let http = response as? HTTPURLResponse, let data = data else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: (http.statusCode, data))
            }.resume()
        }
    }

    func get(url: String, headers: [String: String]) async -> (Int, Data)? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = "GET"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return await withCheckedContinuation { cont in
            session.dataTask(with: req) { data, response, _ in
                guard let http = response as? HTTPURLResponse, let data = data else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: (http.statusCode, data))
            }.resume()
        }
    }
}
