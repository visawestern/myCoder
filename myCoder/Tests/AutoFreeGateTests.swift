import Testing
import Foundation
@testable import myCoder

@Suite("Auto Free upstream error diagnostics")
struct AutoFreeGateTests {
    private let gateBody = #"{"type":"error","error":{"type":"FreeTierError","message":"OpenCode's free tier can only be used from within OpenCode."}}"#
    private let missingSessionBody = #"{"type":"error","error":{"type":"MissingSessionID","message":"x-opencode-session-id is required"}}"#

    @Test func detectsExplicitGateWithoutConflatingMissingSession() {
        #expect(MyCoderAutoFreeError.isFreeTierGate(statusCode: 403, body: gateBody))
        #expect(!MyCoderAutoFreeError.isFreeTierGate(statusCode: 400, body: missingSessionBody))
        #expect(!MyCoderAutoFreeError.isFreeTierGate(statusCode: 400, body: "MissingSessionID: only be used from within OpenCode"))
        #expect(!MyCoderAutoFreeError.isFreeTierGate(statusCode: 429, body: "rate limit"))
        #expect(!MyCoderAutoFreeError.isFreeTierGate(statusCode: 500, body: "boom"))
        #expect(!MyCoderAutoFreeError.isFreeTierGate(statusCode: 403, body: "forbidden"))
    }

    @Test func missingSessionRetainsTheRequiredContext() {
        let error = MyCoderAutoFreeError.mapHttpError(statusCode: 400, body: missingSessionBody, operation: "Free model streaming")
        guard case .apiError(let message) = error else {
            Issue.record("MissingSessionID must remain a context error, got \(error)")
            return
        }
        #expect(message.contains("HTTP 400"))
        #expect(message.contains("MissingSessionID"))
        #expect(message.contains("x-opencode-session-id is required"))
        #expect(!MyCoderAutoFreeClient.shouldHaltFailover(for: error))
    }

    @Test func missingSessionMessageTakesPrecedenceOverGateText() {
        let body = #"{"error":{"type":"MissingSessionID","message":"Missing session ID. Free tier can only be used from within OpenCode."}}"#
        #expect(!MyCoderAutoFreeError.isFreeTierGate(statusCode: 400, body: body))
        #expect(MyCoderAutoFreeError.gateMessage(in: body) == nil)
        guard case .apiError = MyCoderAutoFreeError.streamError(in: body) else {
            Issue.record("An SSE MissingSessionID error must retain its own diagnosis")
            return
        }
    }

    @Test func gateErrorMessageIncludesTheActualBoundedResponse() {
        let error = MyCoderAutoFreeError.mapHttpError(statusCode: 403, body: gateBody, operation: "Free model streaming")
        let text = error.localizedDescription
        #expect(text.contains("FreeTierError"))
        #expect(text.contains("only be used from within OpenCode"))
        #expect(text.contains("configured Zen provider"))
        #expect(!text.contains("verified live"))

        let longText = MyCoderAutoFreeError.freeTierBlocked("server detail " + String(repeating: "x", count: 10_000)).localizedDescription
        #expect(longText.contains("server detail"))
        #expect(longText.count < 700)
    }

    @Test func gateHaltsFailoverInsteadOfCarousel() {
        let error = MyCoderAutoFreeError.mapHttpError(statusCode: 403, body: gateBody, operation: "Free model chat")
        #expect(MyCoderAutoFreeClient.shouldHaltFailover(for: error))
        #expect(!MyCoderAutoFreeClient.shouldSwitchImmediately(for: error))
        #expect(!MyCoderAutoFreeClient.shouldSwitch(for: error, consecutiveFailures: 99))
    }

    @Test(arguments: [400, 403])
    func bareHTTPStatusDoesNotEstablishGate(status: Int) {
        for operation in ["Free model streaming", "Free model chat", "OpenCode free model list"] {
            let error = MyCoderAutoFreeError.mapHttpError(statusCode: status, body: "", operation: operation)
            guard case .modelUnavailable(_, let message) = error else {
                Issue.record("A bare HTTP status must preserve ordinary error mapping, got \(error)")
                continue
            }
            #expect(message.contains("HTTP \(status)"))
            #expect(!MyCoderAutoFreeClient.shouldHaltFailover(for: error))
        }
    }

    @Test func rateLimitRetainsTheServerMessage() {
        let body = #"{"error":{"type":"FreeUsageLimitError","message":"Free usage exceeded, subscribe to Go"}}"#
        let error = MyCoderAutoFreeError.mapHttpError(statusCode: 429, body: body, operation: "Free model streaming")
        guard case .rateLimited(let message) = error else {
            Issue.record("Expected the quota error, got \(error)")
            return
        }
        #expect(message.contains("HTTP 429"))
        #expect(message.contains("FreeUsageLimitError"))
        #expect(message.contains("Free usage exceeded, subscribe to Go"))
    }

    @Test func sseGateRequiresAnErrorEnvelope() {
        #expect(MyCoderAutoFreeError.gateMessage(in: gateBody)?.contains("FreeTierError") == true)
        guard case .freeTierBlocked = MyCoderAutoFreeError.streamError(in: gateBody) else {
            Issue.record("Expected an explicit SSE gate error")
            return
        }
        let content = #"{"choices":[{"delta":{"content":"FreeTierError: only be used from within OpenCode; MissingSessionID"}}]}"#
        #expect(MyCoderAutoFreeError.gateMessage(in: content) == nil)
        #expect(MyCoderAutoFreeError.streamError(in: content) == nil)
        #expect(MyCoderAutoFreeError.gateMessage(in: "FreeTierError") == nil)
    }

    @Test func ordinaryErrorEnvelopeIsNotReportedAsEmptyContent() {
        let body = #"{"error":{"type":"UpstreamError","message":"Provider temporarily unavailable"}}"#
        guard case .apiError(let message) = MyCoderAutoFreeError.streamError(in: body) else {
            Issue.record("Expected the actual upstream SSE error")
            return
        }
        #expect(message.contains("Provider temporarily unavailable"))
    }

    @Test func errorBodyReaderStopsAtItsByteBudget() async throws {
        let counter = AutoFreeByteReadCounter()
        let data = try await MyCoderAutoFreeClient.readErrorBody(AutoFreeCountingBytes(counter: counter), maxBytes: 64)
        #expect(data.count == 64)
        #expect(counter.readCount == 64)
    }

    @Test func streamingHTTPErrorReadsBodyBeforeValidation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutoFreeMissingSessionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = MyCoderAutoFreeClient(session: session)
        do {
            for try await _ in client.chatCompletion(messages: [.init(role: "user", content: "test")]) {}
            Issue.record("Expected the HTTP error")
        } catch let error as MyCoderAutoFreeError {
            guard case .apiError(let message) = error else {
                Issue.record("Expected the body-based MissingSessionID diagnosis, got \(error)")
                return
            }
            #expect(message.contains("HTTP 400"))
            #expect(message.contains("MissingSessionID"))
            #expect(message.contains("x-opencode-session-id is required"))
        }
    }

    @Test func completionRequestCarriesTheReadToolTheFreeTierRequires() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutoFreeCaptureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let path = "/gate-tools"
        AutoFreeCaptureProtocol.setResponse(
            path: path,
            body: "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n"
        )
        let client = MyCoderAutoFreeClient(session: session, baseURL: URL(string: "https://auto-free.test" + path)!)
        for try await _ in client.chatCompletion(messages: [.init(role: "user", content: "test")]) {}

        let body = try #require(AutoFreeCaptureProtocol.lastBody(path: path))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try #require(json["tools"] as? [[String: Any]])
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        #expect(names.contains("read"))
        #expect(json["tool_choice"] as? String == "none")
    }

    @Test func rateLimitedSessionIsReplacedAndTheTurnIsRetried() async throws {
        let suiteName = "com.mycoder.tests.auto-free-session-rotation"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutoFreeRateLimitThenSuccessProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        AutoFreeRateLimitThenSuccessProtocol.reset()

        let sessionID = OpenCodeRequestContext.sessionID(from: "chat-rotation", defaults: defaults)
        let client = MyCoderAutoFreeClient(session: session, sessionDefaults: defaults)
        var text = ""
        for try await event in client.chatCompletion(
            messages: [.init(role: "user", content: "test")],
            context: OpenCodeRequestContext(sessionID: sessionID)
        ) {
            if case .content(let chunk) = event { text += chunk }
        }
        #expect(text == "ok")

        let requests = AutoFreeRateLimitThenSuccessProtocol.captured
        #expect(requests.count == 2)
        let first = requests.first?.value(forHTTPHeaderField: "x-opencode-session")
        let second = requests.last?.value(forHTTPHeaderField: "x-opencode-session")
        #expect(first == sessionID)
        #expect(second != nil)
        #expect(second != first)
        #expect(OpenCodeRequestContext.sessionID(from: "chat-rotation", defaults: defaults) == second)
    }

    @Test func agentToolSetUsesTheUpstreamToolNames() {
        let names = Set(MyCoderAutoFreeClient.agentToolDefinitions().map(\.function.name))
        #expect(names.contains("read"))
        #expect(names.contains("write"))
        #expect(names.contains("edit"))
        #expect(names.contains("bash"))
        #expect(names.contains("read_file") == false)
        #expect(names.contains("run_command") == false)
    }

    @Test func requestsCarryTheEnvironmentBlockTheFreeTierRequires() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutoFreeCaptureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let path = "/gate-environment"
        AutoFreeCaptureProtocol.setResponse(
            path: path,
            body: "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n"
        )
        let client = MyCoderAutoFreeClient(session: session, baseURL: URL(string: "https://auto-free.test" + path)!)
        for try await _ in client.chatCompletion(
            messages: [.init(role: "user", content: "test")],
            projectRoot: "/tmp/project",
            isGitRepo: true
        ) {}

        let body = try #require(AutoFreeCaptureProtocol.lastBody(path: path))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let systemText = messages
            .filter { ($0["role"] as? String) == "system" }
            .compactMap { $0["content"] as? String }
            .joined(separator: "\n")
        #expect(systemText.contains("<env>"))
        #expect(systemText.contains("Working directory: /tmp/project"))
        #expect(systemText.contains("Is directory a git repo: yes"))
        #expect(json["stream"] as? Bool == true)
    }

    @Test func anExistingEnvironmentBlockIsNotDuplicated() {
        let original = MyCoderAutoFreeClient.Message(
            role: "system",
            content: "<env>\n  Working directory: /own\n</env>"
        )
        let messages = MyCoderAutoFreeClient.messagesWithEnvironment(
            [original],
            projectRoot: "/tmp/other",
            isGitRepo: false
        )
        #expect(messages.count == 1)
        #expect(messages.first?.textContent.contains("Working directory: /own") == true)
    }

    @Test func nativeToolCallDeltasBecomeToolCallEvents() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutoFreeCaptureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let path = "/tool-call-deltas"
        AutoFreeCaptureProtocol.setResponse(path: path, body: """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read","arguments":"{\\"path\\""}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\\"README.md\\"}"}}]}}]}

        data: [DONE]

        """)
        let client = MyCoderAutoFreeClient(session: session, baseURL: URL(string: "https://auto-free.test" + path)!)
        var events: [StreamEvent] = []
        for try await event in client.chatCompletion(messages: [.init(role: "user", content: "test")]) {
            events.append(event)
        }
        #expect(events.contains(.toolCall(
            id: "call_1",
            name: "read",
            arguments: #"{"path":"README.md"}"#
        )))
    }

    @Test func nativeToolCallMapsToTheLocalExecutor() throws {
        let call = try #require(MyCoderAutoFreeClient.emulatedToolCall(
            name: "read",
            arguments: #"{"path":"src/main.swift","limit":20}"#
        ))
        #expect(call.name == "read_file")
        #expect(call.arguments["path"] == "src/main.swift")
        #expect(call.arguments["limit"] == "20")

        let edit = try #require(MyCoderAutoFreeClient.emulatedToolCall(
            name: "edit",
            arguments: #"{"filePath":"a.swift","oldString":"x","newString":"y"}"#
        ))
        #expect(edit.name == "edit_file")
        #expect(edit.arguments["path"] == "a.swift")
        #expect(edit.arguments["old"] == "x")
        #expect(edit.arguments["new"] == "y")
    }

    @Test func assistantToolCallAndToolResultMessagesEncodeTheNativeShape() throws {
        let call = MyCoderAutoFreeClient.Message.ToolCall(
            id: "call_1",
            type: "function",
            function: .init(name: "read", arguments: #"{"path":"a.txt"}"#)
        )
        let assistant = MyCoderAutoFreeClient.Message(
            role: "assistant",
            content: "",
            toolCalls: [call]
        )
        let result = MyCoderAutoFreeClient.Message(role: "tool", content: "file body", toolCallID: "call_1")
        let data = try JSONEncoder().encode([assistant, result])
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let encodedCall = try #require((json[0]["tool_calls"] as? [[String: Any]])?.first)
        #expect(encodedCall["id"] as? String == "call_1")
        #expect((encodedCall["function"] as? [String: Any])?["name"] as? String == "read")
        #expect(json[1]["role"] as? String == "tool")
        #expect(json[1]["tool_call_id"] as? String == "call_1")
        #expect(json[1]["content"] as? String == "file body")
    }
}

private final class AutoFreeByteReadCounter {
    var readCount = 0
}

private struct AutoFreeCountingBytes: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = UInt8
    let counter: AutoFreeByteReadCounter

    func makeAsyncIterator() -> Self { self }

    mutating func next() async -> UInt8? {
        counter.readCount += 1
        return 120
    }
}

private final class AutoFreeMissingSessionProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let body = #"{"error":{"type":"MissingSessionID","message":"x-opencode-session-id is required"}}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class AutoFreeRateLimitThenSuccessProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        requests.removeAll()
    }

    static var captured: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let attempt = Self.requests.count
        Self.lock.unlock()

        let status: Int
        let body: String
        let contentType: String
        if attempt == 1 {
            status = 429
            body = #"{"error":{"type":"FreeUsageLimitError","message":"Free usage limit reached"}}"#
            contentType = "application/json"
        } else {
            status = 200
            body = "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n"
            contentType = "text/event-stream"
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class AutoFreeCaptureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responses: [String: String] = [:]
    private static var bodies: [String: Data] = [:]

    static func setResponse(path: String, body: String) {
        lock.lock()
        defer { lock.unlock() }
        responses[path] = body
        bodies[path] = nil
    }

    static func lastBody(path: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return bodies[path]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let body = Self.captureBody(request)
        Self.lock.lock()
        let key = Self.responses.keys.first { path.hasPrefix($0) }
        if let key { Self.bodies[key] = body }
        let response = key.flatMap { Self.responses[$0] } ?? ""
        Self.lock.unlock()

        let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                   headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func captureBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
