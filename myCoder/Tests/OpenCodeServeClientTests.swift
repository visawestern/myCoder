import Testing
import Foundation
@testable import myCoder

/// OpenCode headless-server session API (verified live against
/// `opencode serve` 1.18.29: POST /session → POST /session/:id/message).
@Suite("OpenCode serve session client (OC-2)")
struct OpenCodeServeClientTests {

    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    @Test func sessionIDExtractsFromCreateResponse() {
        let data = json(#"{"id":"ses_abc123","slug":"x","title":"probe"}"#)
        #expect(OpenCodeServeClient.extractSessionID(from: data) == "ses_abc123")
        #expect(OpenCodeServeClient.extractSessionID(from: json("{}")) == nil)
    }

    @Test func textJoinsTextParts() {
        let data = json("""
        {"info":{"id":"m1"},"parts":[
          {"type":"step-start","id":"p0"},
          {"type":"text","text":"he"},
          {"type":"text","text":"llo"},
          {"type":"tool","state":{"status":"completed"}}
        ]}
        """)
        #expect(OpenCodeServeClient.extractText(from: data) == "hello")
        #expect(OpenCodeServeClient.extractText(from: json(#"{"info":{},"parts":[]}"#)) == nil)
    }

    @Test func messageBodyCarriesModelAndText() throws {
        let body = OpenCodeServeClient.messageBody(modelID: "big-pickle", text: "hi", providerID: "ollama-gemma-cloud")
        let data = try JSONSerialization.data(withJSONObject: body)
        let back = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let model = back?["model"] as? [String: Any]
        #expect(model?["providerID"] as? String == "ollama-gemma-cloud")
        #expect(model?["modelID"] as? String == "big-pickle")
        let parts = back?["parts"] as? [[String: Any]]
        #expect(parts?.first?["text"] as? String == "hi")
    }

    @Test func sendCreatesSessionThenMessages() async throws {
        let session = json(#"{"id":"ses_1","slug":"x"}"#)
        let answer = json(#"{"info":{"id":"m1"},"parts":[{"type":"text","text":"ok"}]}"#)
        // Two-step scripted transport.
        final class Script: DirectChatTransport, @unchecked Sendable {
            var calls: [String] = []
            func post(url: String, headers: [String : String], body: Data) async -> (Int, Data)? {
                calls.append(url)
                if url.hasSuffix("/session") { return (200, session) }
                return (200, answer)
            }
            func get(url: String, headers: [String : String]) async -> (Int, Data)? { nil }
            let session: Data
            let answer: Data
            init(session: Data, answer: Data) { self.session = session; self.answer = answer }
        }
        let transport = Script(session: session, answer: answer)
        let result = try await OpenCodeServeClient.send(
            baseURL: "http://127.0.0.1:4096", headers: [:],
            modelID: "big-pickle", text: "hi", sessionID: nil,
            transport: transport)
        #expect(result.content == "ok")
        #expect(result.sessionID == "ses_1")
        #expect(transport.calls.count == 2)
        #expect(transport.calls[0].hasSuffix("/session"))
        #expect(transport.calls[1].contains("/session/ses_1/message"))
    }

    @Test func sendReusesGivenSession() async throws {
        let answer = json(#"{"info":{"id":"m1"},"parts":[{"type":"text","text":"again"}]}"#)
        final class Script: DirectChatTransport, @unchecked Sendable {
            var calls: [String] = []
            let answer: Data
            init(answer: Data) { self.answer = answer }
            func post(url: String, headers: [String : String], body: Data) async -> (Int, Data)? {
                calls.append(url)
                return (200, answer)
            }
            func get(url: String, headers: [String : String]) async -> (Int, Data)? { nil }
        }
        let transport = Script(answer: answer)
        let result = try await OpenCodeServeClient.send(
            baseURL: "http://127.0.0.1:4096", headers: [:],
            modelID: "big-pickle", text: "hi", sessionID: "ses_9",
            transport: transport)
        #expect(result.content == "again")
        #expect(result.sessionID == "ses_9")
        #expect(transport.calls.count == 1)
    }

    @Test func unauthorizedIsActionable() async {
        struct DenyAll: DirectChatTransport {
            func post(url: String, headers: [String : String], body: Data) async -> (Int, Data)? {
                (401, Data())
            }
            func get(url: String, headers: [String : String]) async -> (Int, Data)? { nil }
        }
        do {
            _ = try await OpenCodeServeClient.send(
                baseURL: "http://127.0.0.1:4096", headers: [:],
                modelID: "big-pickle", text: "hi", sessionID: "ses_9",
                transport: DenyAll())
            Issue.record("expected throw")
        } catch let error as OpenCodeServeError {
            #expect(error == .unauthorized)
            #expect(error.localizedDescription.contains("password") || error.localizedDescription.contains("auth"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func jsonContentTypeIsSet() async throws {
        let answer = json(#"{"info":{"id":"m1"},"parts":[{"type":"text","text":"ok"}]}"#)
        final class Cap: DirectChatTransport, @unchecked Sendable {
            var headers: [[String: String]] = []
            let answer: Data
            init(answer: Data) { self.answer = answer }
            func post(url: String, headers: [String : String], body: Data) async -> (Int, Data)? {
                self.headers.append(headers)
                return (200, answer)
            }
            func get(url: String, headers: [String : String]) async -> (Int, Data)? { nil }
        }
        let transport = Cap(answer: answer)
        _ = try await OpenCodeServeClient.send(
            baseURL: "http://127.0.0.1:4096", headers: ["Authorization": "Basic eA=="],
            modelID: "big-pickle", text: "hi", sessionID: "ses_9",
            transport: transport)
        #expect(transport.headers.first?["Content-Type"] == "application/json")
        #expect(transport.headers.first?["Authorization"] == "Basic eA==")
    }

    // MARK: - SSE streaming (prompt_async + /event)

    private func deltaLine(session: String, message: String, text: String) -> String {
        "data: {\"id\":\"evt_1\",\"type\":\"message.part.delta\"," +
        "\"properties\":{\"sessionID\":\"\(session)\",\"messageID\":\"\(message)\"," +
        "\"partID\":\"prt_1\",\"field\":\"text\",\"delta\":\"\(text)\"}}"
    }

    private func idleLine(session: String) -> String {
        "data: {\"id\":\"evt_2\",\"type\":\"session.idle\"," +
        "\"properties\":{\"sessionID\":\"\(session)\"}}"
    }

    @Test func promptAsyncURLTargetsSession() {
        #expect(OpenCodeServeClient.promptAsyncURL(baseURL: "http://127.0.0.1:4096", sessionID: "ses_1")
            == "http://127.0.0.1:4096/session/ses_1/prompt_async")
        #expect(OpenCodeServeClient.eventURL(baseURL: "http://127.0.0.1:4096/") == "http://127.0.0.1:4096/event")
    }

    @Test func streamEventParsesDeltaAndIdle() {
        let sid = "ses_9", mid = "msg_7"
        let delta = OpenCodeServeClient.parseStreamEvent(deltaLine(session: sid, message: mid, text: "Hi"))
        guard case .delta(let ds, let dm, let text)? = delta else {
            Issue.record("expected delta, got \(String(describing: delta))")
            return
        }
        #expect(ds == sid)
        #expect(dm == mid)
        #expect(text == "Hi")
        guard case .idle(let idleSID)? = OpenCodeServeClient.parseStreamEvent(idleLine(session: sid)) else {
            Issue.record("expected idle")
            return
        }
        #expect(idleSID == sid)
        #expect(OpenCodeServeClient.parseStreamEvent(":comment") == nil)
        #expect(OpenCodeServeClient.parseStreamEvent("data: not-json") == nil)
        #expect(OpenCodeServeClient.parseStreamEvent("data: {\"type\":\"server.heartbeat\"}") == nil)
    }

    @Test func streamSendYieldsDeltasThenFinishesOnIdle() async throws {
        struct ScriptEvents: OpenCodeEventSource {
            let lines: [String]
            func lines(url: String, headers: [String: String]) -> AsyncThrowingStream<String, Error> {
                AsyncThrowingStream { continuation in
                    for line in lines { continuation.yield(line) }
                    continuation.finish()
                }
            }
        }
        let sid = "ses_1", mid = "msg_1"
        let events = ScriptEvents(lines: [
            ":connected",
            deltaLine(session: sid, message: mid, text: "Hel"),
            deltaLine(session: "ses_OTHER", message: "msg_X", text: "SHOULD-BE-IGNORED"),
            deltaLine(session: sid, message: mid, text: "lo"),
            idleLine(session: sid),
        ])
        final class Posts: DirectChatTransport, @unchecked Sendable {
            func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? {
                (204, Data())
            }
            func get(url: String, headers: [String: String]) async -> (Int, Data)? { nil }
        }
        let (returnedSID, stream) = try await OpenCodeServeClient.streamSend(
            baseURL: "http://127.0.0.1:4096", headers: [:],
            modelID: "big-pickle", text: "hi", sessionID: sid,
            transport: Posts(), events: events)
        #expect(returnedSID == sid)
        var chunks: [String] = []
        for try await event in stream {
            if case .content(let text) = event { chunks.append(text) }
        }
        #expect(chunks == ["Hel", "lo"])
    }

    @Test func streamSendThrowsWhenIdleNeverArrives() async {
        struct EmptyEvents: OpenCodeEventSource {
            func lines(url: String, headers: [String: String]) -> AsyncThrowingStream<String, Error> {
                AsyncThrowingStream { $0.finish() }
            }
        }
        final class Posts: DirectChatTransport, @unchecked Sendable {
            func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? {
                (204, Data())
            }
            func get(url: String, headers: [String: String]) async -> (Int, Data)? { nil }
        }
        do {
            let (_, stream) = try await OpenCodeServeClient.streamSend(
                baseURL: "http://127.0.0.1:4096", headers: [:],
                modelID: "big-pickle", text: "hi", sessionID: "ses_1",
                transport: Posts(), events: EmptyEvents())
            for try await _ in stream {}
            Issue.record("expected throw")
        } catch let error as OpenCodeServeError {
            #expect(error == .emptyResponse)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func messageListURLTargetsSessionMessages() {
        #expect(OpenCodeServeClient.messageListURL(baseURL: "http://127.0.0.1:4096", sessionID: "ses_1")
            == "http://127.0.0.1:4096/session/ses_1/message")
    }

    @Test func fetchLastAssistantTextSkipsUserMessages() async {
        let list = """
        [{"info":{"id":"m1","role":"user"},"parts":[{"type":"text","text":"hi"}]},
         {"info":{"id":"m2","role":"assistant"},"parts":[{"type":"step-start"},{"type":"text","text":"Hel"},{"type":"text","text":"lo"}]},
         {"info":{"id":"m3","role":"user"},"parts":[{"type":"text","text":"again?"}]}]
        """.data(using: .utf8)!
        struct History: DirectChatTransport {
            let list: Data
            func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? { nil }
            func get(url: String, headers: [String: String]) async -> (Int, Data)? {
                (200, list)
            }
        }
        let text = await OpenCodeServeClient.fetchLastAssistantText(
            baseURL: "http://127.0.0.1:4096", headers: [:],
            sessionID: "ses_1", transport: History(list: list))
        #expect(text == "Hello")
    }

    @Test func fetchLastAssistantTextIsNilWhenNoAssistantText() async {
        let list = """
        [{"info":{"id":"m1","role":"user"},"parts":[{"type":"text","text":"hi"}]}]
        """.data(using: .utf8)!
        struct History: DirectChatTransport {
            let list: Data
            func post(url: String, headers: [String: String], body: Data) async -> (Int, Data)? { nil }
            func get(url: String, headers: [String: String]) async -> (Int, Data)? {
                (200, list)
            }
        }
        let text = await OpenCodeServeClient.fetchLastAssistantText(
            baseURL: "http://127.0.0.1:4096", headers: [:],
            sessionID: "ses_1", transport: History(list: list))
        #expect(text == nil)
    }
}
