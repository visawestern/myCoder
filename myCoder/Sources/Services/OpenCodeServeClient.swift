import Foundation

/// Errors from the local OpenCode headless server (verified live against
/// `opencode serve` 1.18.29: POST /session → POST /session/:id/message).
enum OpenCodeServeError: Error, Equatable, LocalizedError {
    case transport(String)
    case unauthorized
    case http(status: Int, body: String)
    case decode
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .transport(let msg):
            return "Could not reach the local OpenCode server: \(msg). Start it with `opencode serve --port 4096`."
        case .unauthorized:
            return "The local OpenCode server requires basic auth (HTTP 401). Set the username/password on the OpenCode local provider — the same password as OPENCODE_SERVER_PASSWORD."
        case .http(let status, let body):
            let detail = body.isEmpty ? "" : " — \(body.prefix(200))"
            return "Local OpenCode server returned HTTP \(status)\(detail)"
        case .decode:
            return "The local OpenCode server response could not be parsed (unexpected format)."
        case .emptyResponse:
            return "The local OpenCode server returned no text."
        }
    }
}

/// In-memory map from myCoder chat id → opencode serve session id (OC-3).
/// Follow-up turns reuse the server-side session so context carries over.
/// Process-local only (documented follow-up: persist per project DB).
final class OpenCodeServeSessionStore: @unchecked Sendable {
    static let shared = OpenCodeServeSessionStore()
    private let lock = NSLock()
    private var map: [String: String] = [:]

    func sessionID(for chatID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return map[chatID]
    }

    func remember(sessionID: String, for chatID: String) {
        lock.lock(); defer { lock.unlock() }
        map[chatID] = sessionID
    }

    func forget(chatID: String) {
        lock.lock(); defer { lock.unlock() }
        map.removeValue(forKey: chatID)
    }
}

/// Thin client for a user-run `opencode serve` (their own OAuth identity —
/// the only path that passes the upstream free-tier gate; anonymous header
/// tricks are gated server-side, probed live 2026-10-13).
/// Transport-injected for tests; production passes URLSession-backed transport.
enum OpenCodeServeClient {
    struct SendResult: Equatable {
        let content: String
        let sessionID: String
    }

    static func sessionURL(baseURL: String) -> String {
        baseURL.hasSuffix("/") ? "\(baseURL)session" : "\(baseURL)/session"
    }

    static func messageURL(baseURL: String, sessionID: String) -> String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return "\(base)/session/\(sessionID)/message"
    }

    static func messageBody(modelID: String, text: String, providerID: String = "opencode") -> [String: Any] {
        [
            "model": ["providerID": providerID, "modelID": modelID],
            "parts": [["type": "text", "text": text]],
        ]
    }

    static func extractSessionID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String, !id.isEmpty else { return nil }
        return id
    }

    /// Join all text parts; tool/step parts are skipped (same contract as the
    /// chat UI: only vendor-produced content completes a turn).
    static func extractText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parts = json["parts"] as? [[String: Any]] else { return nil }
        let text = parts.compactMap { part -> String? in
            guard part["type"] as? String == "text" else { return nil }
            return part["text"] as? String
        }.joined()
        return text.isEmpty ? nil : text
    }

    /// Send one turn: create a session unless `sessionID` is given, post the
    /// message, return the model text + the session to reuse.
    static func send(baseURL: String,
                     headers: [String: String],
                     modelID: String,
                     text: String,
                     providerID: String = "opencode",
                     sessionID: String? = nil,
                     transport: DirectChatTransport = URLSessionDirectChatTransport()) async throws -> SendResult {
        // The serve API speaks JSON; transports leave Content-Type unset.
        var jsonHeaders = headers
        jsonHeaders["Content-Type"] = "application/json"
        let sid: String
        if let sessionID, !sessionID.isEmpty {
            sid = sessionID
        } else {
            let body = try JSONSerialization.data(withJSONObject: ["title": String(text.prefix(60))])
            guard let (status, data) = await transport.post(url: sessionURL(baseURL: baseURL), headers: jsonHeaders, body: body) else {
                throw OpenCodeServeError.transport("No response from \(baseURL)")
            }
            guard status != 401 else { throw OpenCodeServeError.unauthorized }
            guard (200..<300).contains(status), let id = extractSessionID(from: data) else {
                throw OpenCodeServeError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
            }
            sid = id
        }
        let msgBody = try JSONSerialization.data(withJSONObject: messageBody(modelID: modelID, text: text, providerID: providerID))
        guard let (status, data) = await transport.post(url: messageURL(baseURL: baseURL, sessionID: sid), headers: jsonHeaders, body: msgBody) else {
            throw OpenCodeServeError.transport("No response from \(baseURL)")
        }
        guard status != 401 else { throw OpenCodeServeError.unauthorized }
        guard (200..<300).contains(status) else {
            throw OpenCodeServeError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let content = extractText(from: data),
              ProviderResponseValidationLogic.hasVisibleContent(content) else {
            throw OpenCodeServeError.emptyResponse
        }
        return SendResult(content: content, sessionID: sid)
    }

    // MARK: - SSE streaming (prompt_async + /event)

    static func promptAsyncURL(baseURL: String, sessionID: String) -> String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return "\(base)/session/\(sessionID)/prompt_async"
    }

    static func eventURL(baseURL: String) -> String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return "\(base)/event"
    }

    static func messageListURL(baseURL: String, sessionID: String) -> String {
        messageURL(baseURL: baseURL, sessionID: sessionID)
    }

    /// Best-effort recovery when the SSE stream dies after prompt_async was
    /// accepted: re-sending would duplicate the user message, so read back
    /// the latest assistant text instead. Returns nil when unavailable —
    /// the caller then falls back to the blocking send.
    static func fetchLastAssistantText(baseURL: String,
                                       headers: [String: String],
                                       sessionID: String,
                                       transport: DirectChatTransport = URLSessionDirectChatTransport()) async -> String? {
        guard let (status, data) = await transport.get(url: messageListURL(baseURL: baseURL, sessionID: sessionID), headers: headers),
              (200..<300).contains(status),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        for entry in list.reversed() {
            guard let info = entry["info"] as? [String: Any],
                  info["role"] as? String == "assistant",
                  let parts = entry["parts"] as? [[String: Any]] else { continue }
            let text = parts.compactMap { part -> String? in
                guard part["type"] as? String == "text" else { return nil }
                return part["text"] as? String
            }.joined()
            if !text.isEmpty { return text }
        }
        return nil
    }

    /// Parse one SSE line from the serve `/event` stream. Returns nil for
    /// comments, heartbeats, and unrelated event types.
    static func parseStreamEvent(_ line: String) -> OpenCodeStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let json = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String,
              let props = obj["properties"] as? [String: Any],
              let sessionID = props["sessionID"] as? String else { return nil }
        switch type {
        case "message.part.delta":
            guard let messageID = props["messageID"] as? String,
                  props["field"] as? String == "text",
                  let delta = props["delta"] as? String else { return nil }
            return .delta(sessionID: sessionID, messageID: messageID, text: delta)
        case "session.idle":
            return .idle(sessionID: sessionID)
        default:
            return nil
        }
    }

    /// Stream one turn: prompt_async, then text deltas for our session until
    /// its `session.idle`. Returns the serve session id plus the live event
    /// stream. Deltas from other sessions are ignored; a stream that ends
    /// with zero deltas throws `.emptyResponse` so the caller can fall back
    /// to the blocking `send`.
    static func streamSend(baseURL: String,
                           headers: [String: String],
                           modelID: String,
                           text: String,
                           providerID: String = "opencode",
                           sessionID: String? = nil,
                           transport: DirectChatTransport = URLSessionDirectChatTransport(),
                           events: OpenCodeEventSource = URLSessionEventSource()) async throws -> (String, AsyncThrowingStream<StreamEvent, Error>) {
        var jsonHeaders = headers
        jsonHeaders["Content-Type"] = "application/json"
        let sid: String
        if let sessionID, !sessionID.isEmpty {
            sid = sessionID
        } else {
            let body = try JSONSerialization.data(withJSONObject: ["title": String(text.prefix(60))])
            guard let (status, data) = await transport.post(url: sessionURL(baseURL: baseURL), headers: jsonHeaders, body: body) else {
                throw OpenCodeServeError.transport("No response from \(baseURL)")
            }
            guard status != 401 else { throw OpenCodeServeError.unauthorized }
            guard (200..<300).contains(status), let id = extractSessionID(from: data) else {
                throw OpenCodeServeError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
            }
            sid = id
        }
        let msgBody = try JSONSerialization.data(withJSONObject: messageBody(modelID: modelID, text: text, providerID: providerID))
        guard let (status, data) = await transport.post(url: promptAsyncURL(baseURL: baseURL, sessionID: sid), headers: jsonHeaders, body: msgBody) else {
            throw OpenCodeServeError.transport("No response from \(baseURL)")
        }
        guard status != 401 else { throw OpenCodeServeError.unauthorized }
        guard (200..<300).contains(status) else {
            throw OpenCodeServeError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        let stream = AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    var emitted = 0
                    for try await line in events.lines(url: eventURL(baseURL: baseURL), headers: headers) {
                        guard let event = parseStreamEvent(line) else { continue }
                        switch event {
                        case .delta(let dsid, _, let deltaText) where dsid == sid:
                            guard !deltaText.isEmpty else { continue }
                            emitted += 1
                            continuation.yield(.content(deltaText))
                        case .idle(let isid) where isid == sid:
                            continuation.finish()
                            return
                        default:
                            continue
                        }
                    }
                    if emitted == 0 {
                        continuation.finish(throwing: OpenCodeServeError.emptyResponse)
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return (sid, stream)
    }
}

/// One parsed `/event` line relevant to streaming.
enum OpenCodeStreamEvent: Equatable {
    /// Text delta for an assistant message part in the given session.
    case delta(sessionID: String, messageID: String, text: String)
    /// The given session went idle (turn complete).
    case idle(sessionID: String)
}

/// Source of raw SSE lines from the serve `/event` endpoint.
/// Scripted in tests; live over URLSession in production.
protocol OpenCodeEventSource {
    func lines(url: String, headers: [String: String]) -> AsyncThrowingStream<String, Error>
}

/// Live SSE reader: yields raw lines from a `text/event-stream` response.
struct URLSessionEventSource: OpenCodeEventSource {
    func lines(url: String, headers: [String: String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let requestURL = URL(string: url) else {
                        throw OpenCodeServeError.transport("Bad event URL: \(url)")
                    }
                    var request = URLRequest(url: requestURL)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    for (field, value) in headers {
                        request.setValue(value, forHTTPHeaderField: field)
                    }
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw OpenCodeServeError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: "")
                    }
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
