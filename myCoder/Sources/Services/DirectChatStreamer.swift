import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One visible slice of a streaming completion.
struct DirectChatStreamUpdate: Equatable {
    let content: String
    let reasoning: String
    let usage: UsageCapture?
}

/// Accumulates an OpenAI-compatible SSE stream (`stream: true`) into readable
/// text. Kept separate from the network call so the delta/`[DONE]`/usage
/// parsing can be tested without a server.
struct DirectChatStreamAccumulator {
    private(set) var content = ""
    private(set) var reasoning = ""
    private(set) var usage: UsageCapture?
    private(set) var sawDataLine = false
    /// Concatenated non-SSE lines. Some providers ignore `stream: true` and
    /// answer with one plain JSON body; that body is parsed on completion
    /// instead of being mistaken for streaming deltas.
    private(set) var rawText = ""

    /// Feed one line of the HTTP body. Returns the new visible state only when
    /// this line actually changed the answer.
    mutating func ingest(_ line: String, contextBytes: Int = 0) -> DirectChatStreamUpdate? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return nil }
        guard trimmed.hasPrefix("data:") else {
            rawText += line + "\n"
            return nil
        }

        sawDataLine = true
        let payload = String(trimmed.dropFirst("data:".count))
            .trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return snapshot(changed: true) }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var changed = false
        if let choice = (json["choices"] as? [[String: Any]])?.first {
            if let delta = choice["delta"] as? [String: Any],
               apply(delta) {
                changed = true
            }
            // A provider may resend the whole message instead of a delta.
            if let message = choice["message"] as? [String: Any],
               applyFullMessage(message) {
                changed = true
            }
        }
        // Ollama-native shape, in case the endpoint proxies /api/chat.
        if let message = json["message"] as? [String: Any],
           applyFullMessage(message) {
            changed = true
        }
        if let parsedUsage = DirectChatClient.usage(from: json, contextBytes: contextBytes) {
            usage = parsedUsage
            changed = true
        }
        return changed ? snapshot(changed: true) : nil
    }

    var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func result() -> DirectChatResult {
        DirectChatResult(content: content, reasoning: reasoning, usage: usage)
    }

    /// Result of a response body that was not SSE at all.
    func fallbackResult(contextBytes: Int) -> DirectChatResult? {
        guard !rawText.isEmpty else { return nil }
        let data = Data(rawText.utf8)
        return DirectChatClient.parseResponse(data, contextBytes: contextBytes)
    }

    // MARK: - Private

    private mutating func apply(_ channel: [String: Any]) -> Bool {
        var changed = false
        if let text = Self.textValue(channel["content"]) {
            content += text
            changed = true
        }
        if let thinking = DirectChatClient.reasoningText(in: channel) {
            reasoning += thinking
            changed = true
        }
        return changed
    }

    /// Full-message chunks replace (not append) the visible text: the provider
    /// is resending cumulative content.
    private mutating func applyFullMessage(_ message: [String: Any]) -> Bool {
        var changed = false
        if let text = Self.textValue(message["content"]), text != content {
            content = text
            changed = true
        }
        if let thinking = DirectChatClient.reasoningText(in: message), thinking != reasoning {
            reasoning = thinking
            changed = true
        }
        return changed
    }

    /// `content` may be a plain string or an array of `{type: "text", text: …}`
    /// blocks (some gateways stream the multimodal form).
    static func textValue(_ raw: Any?) -> String? {
        if let text = raw as? String { return text }
        if let blocks = raw as? [[String: Any]] {
            let joined = blocks.compactMap { block -> String? in
                if let text = block["text"] as? String { return text }
                if let text = block["content"] as? String { return text }
                return nil
            }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private func snapshot(changed: Bool) -> DirectChatStreamUpdate? {
        guard changed else { return nil }
        return DirectChatStreamUpdate(content: content, reasoning: reasoning, usage: usage)
    }
}

enum DirectChatStreamer {
    /// Stream a chat completion. The callback receives throttled, cumulative
    /// text so the message can be redrawn while tokens arrive; the returned
    /// result is the complete answer for the turn.
    static func stream(
        baseURL: String,
        apiKey: String?,
        model: String,
        messages: [DirectChatMessage],
        parameters: ModelCallParameters = ModelCallParameters(),
        timeout: TimeInterval = 300,
        updateInterval: TimeInterval = 0.12,
        onUpdate: @escaping @MainActor (DirectChatStreamUpdate) -> Void
    ) async throws -> DirectChatResult {
        let url = baseURL.hasSuffix("/") ? "\(baseURL)chat/completions" : "\(baseURL)/chat/completions"
        guard let requestURL = URL(string: url) else {
            throw DirectChatError.transport("Invalid provider URL: \(url)")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let body = DirectChatClient.requestBody(
            model: model,
            messages: messages,
            parameters: parameters,
            stream: true
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DirectChatError.transport("No response from \(url)")
        }
        guard (200..<300).contains(http.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let text = String(data: errorData, encoding: .utf8) ?? ""
            throw DirectChatError.http(status: http.statusCode, body: text)
        }

        let contextBytes = messages.reduce(0) { $0 + $1.content.utf8.count }
        var accumulator = DirectChatStreamAccumulator()
        var lastEmit = Date.distantPast

        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            guard let update = accumulator.ingest(line, contextBytes: contextBytes) else { continue }
            let now = Date()
            if now.timeIntervalSince(lastEmit) >= updateInterval {
                lastEmit = now
                await MainActor.run { onUpdate(update) }
            }
        }

        // A provider that ignored `stream: true` sent one JSON body.
        if !accumulator.sawDataLine, let fallback = accumulator.fallbackResult(contextBytes: contextBytes) {
            return fallback
        }
        guard !accumulator.isEmpty else {
            if accumulator.sawDataLine {
                throw DirectChatError.emptyResponse
            }
            throw DirectChatError.decode
        }
        // Always deliver the final state, even if the throttle skipped it.
        let final = DirectChatStreamUpdate(
            content: accumulator.content,
            reasoning: accumulator.reasoning,
            usage: accumulator.usage
        )
        await MainActor.run { onUpdate(final) }
        return accumulator.result()
    }
}
