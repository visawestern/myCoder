import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Diagnostic logging of raw server responses (SSE lines, updates, agent
/// iterations). Enabled when the flag file `/tmp/mycoder_sse_enabled`
/// exists (or `MYCODER_LOG_SSE=1` is set — GUI apps rarely inherit env).
/// Writes plain text lines to log files so the exact server order can be
/// inspected after a turn.
enum StreamDiagnostics {
    static var isEnabled: Bool {
        // Temporary: unconditional in debug builds to trace the send path.
        // Final gate: flag file /tmp/mycoder_sse_enabled or env var.
        if ProcessInfo.processInfo.environment["MYCODER_LOG_SSE"] == "1" {
            return true
        }
        if FileManager.default.fileExists(atPath: "/tmp/mycoder_sse_enabled") {
            return true
        }
        return false
    }

    private static let lock = NSLock()
    private static var openedFiles: Set<String> = []

    static func log(_ line: String, file: String = "/tmp/mycoder_sse.log") {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if !openedFiles.contains(file) {
            // Truncate once per process for a fresh log.
            try? "".write(toFile: file, atomically: true, encoding: .utf8)
            openedFiles.insert(file)
        }
        if let handle = FileHandle(forWritingAtPath: file) {
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8) ?? Data())
            try? handle.close()
        }
    }
}

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
    /// True when the provider sent an encrypted reasoning channel (we cannot
    /// show its content, but we must not pretend the model never reasoned).
    private(set) var sawEncryptedReasoning = false
    /// Concatenated non-SSE lines. Some providers ignore `stream: true` and
    /// answer with one plain JSON body; that body is parsed on completion
    /// instead of being mistaken for streaming deltas.
    private(set) var rawText = ""
    /// Raw `data:` payloads in arrival order (debug "Сырой ответ" button).
    private(set) var rawEvents: [String] = []

    /// The visible reasoning text: real thinking when available, otherwise an
    /// honest placeholder for the encrypted channel.
    var visibleReasoning: String {
        if !reasoning.isEmpty { return reasoning }
        if sawEncryptedReasoning { return "🧠 Рассуждение получено (зашифровано провайдером)" }
        return ""
    }

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
        if !payload.isEmpty {
            rawEvents.append(payload)
        }
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
            && visibleReasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func result() -> DirectChatResult {
        DirectChatResult(content: content, reasoning: visibleReasoning, usage: usage,
                         rawEvents: rawEvents)
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
        } else if DirectChatClient.hasEncryptedReasoning(in: channel), !sawEncryptedReasoning {
            sawEncryptedReasoning = true
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
        } else if DirectChatClient.hasEncryptedReasoning(in: message), !sawEncryptedReasoning {
            sawEncryptedReasoning = true
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
        return DirectChatStreamUpdate(content: content, reasoning: visibleReasoning, usage: usage)
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
        if StreamDiagnostics.isEnabled {
            StreamDiagnostics.log("[REQ] \(url) body=\(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")")
        }

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
            if StreamDiagnostics.isEnabled {
                StreamDiagnostics.log("[SSE] " + line)
            }
            guard let update = accumulator.ingest(line, contextBytes: contextBytes) else { continue }
            if StreamDiagnostics.isEnabled {
                StreamDiagnostics.log("[UPDATE] content+=\(update.content.count) reasoning+=\(update.reasoning.count) usage=\(update.usage.map { "\($0.totalTokens)" } ?? "nil")")
            }
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
