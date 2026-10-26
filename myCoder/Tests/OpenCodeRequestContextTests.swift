import Testing
import Foundation
@testable import myCoder

@Suite("OpenCode request context")
struct OpenCodeRequestContextTests {
    private let upstreamAlphabet = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    @Test("Session ids use the upstream ses_ shape")
    func sessionIDNormalization() {
        let mapped = OpenCodeRequestContext.sessionID(from: "550E8400-E29B-41D4-A716-446655440000")
        #expect(mapped.hasPrefix("ses_"))
        #expect(mapped.count == 4 + OpenCodeRequestContext.identifierBodyLength)
        #expect(mapped.dropFirst(4).allSatisfy { upstreamAlphabet.contains($0) })
        #expect(OpenCodeRequestContext.sessionID(from: "550E8400-E29B-41D4-A716-446655440000") == mapped)
        #expect(OpenCodeRequestContext.sessionID(from: mapped) == mapped)
        #expect(OpenCodeRequestContext.sessionID(from: "").hasPrefix("ses_"))
        #expect(OpenCodeRequestContext.sessionID(from: "chat-123") != OpenCodeRequestContext.sessionID(from: "chat-124"))
    }

    @Test("Request ids use the upstream msg_ shape")
    func requestIDShape() {
        let requestID = OpenCodeRequestContext.requestID()
        #expect(requestID.hasPrefix("msg_"))
        #expect(requestID.count == 4 + OpenCodeRequestContext.identifierBodyLength)
        #expect(requestID.dropFirst(4).allSatisfy { upstreamAlphabet.contains($0) })
    }

    @Test("Identifier time parts match the official client capture")
    func identifierTimePartMatchesCapture() {
        // Captured from the official client (opencode 1.19.4): the session id
        // is descending, the message id ascending, and both encode the
        // creation timestamp in their first 12 hex characters.
        let session = OpenCodeRequestContext.identifier(
            prefix: "ses",
            descending: true,
            timestamp: 6_168_390_472
        )
        #expect(session.hasPrefix("ses_e9055d4b7ffe"))
        let message = OpenCodeRequestContext.identifier(
            prefix: "msg",
            descending: false,
            timestamp: 6_168_390_525
        )
        #expect(message.hasPrefix("msg_16faa2b7d001"))
        #expect(session.count == 4 + OpenCodeRequestContext.identifierBodyLength)
        #expect(message.count == 4 + OpenCodeRequestContext.identifierBodyLength)
    }

    @Test("Session identifiers stay stable per chat and survive a restart")
    func sessionIdentifierPersistence() {
        let suiteName = "com.mycoder.tests.opencode-session-identifiers"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = OpenCodeRequestContext.sessionID(from: "chat-persist", defaults: defaults)
        let second = OpenCodeRequestContext.sessionID(from: "chat-persist", defaults: defaults)
        #expect(first == second)
        #expect(first.hasPrefix("ses_"))
        #expect(OpenCodeRequestContext.sessionID(from: "chat-other", defaults: defaults) != first)

        let reloaded = UserDefaults(suiteName: suiteName)
        #expect(reloaded?.data(forKey: MyCoderDefaults.key("opencode.sessionIdentifiers")) != nil)
        #expect(OpenCodeRequestContext.sessionID(from: "chat-persist", defaults: reloaded ?? defaults) == first)
    }

    @Test("Project ids are opaque 40 hex characters")
    func projectIDShape() {
        let project = OpenCodeRequestContext.projectID(fromPath: "/Users/apple/projects/demo")
        #expect(project?.count == OpenCodeRequestContext.projectIdentifierLength)
        #expect(project?.allSatisfy { $0.isHexDigit } == true)
        #expect(project != "/Users/apple/projects/demo")
        #expect(OpenCodeRequestContext.projectID(fromPath: "") == nil)
        #expect(OpenCodeRequestContext.projectID(fromPath: "  ") == nil)
    }

    @Test("Headers mirror the official client contract")
    func headerContract() {
        let context = OpenCodeRequestContext(
            sessionID: "ses_abc",
            projectID: "0123456789abcdef0123456789abcdef01234567",
            requestID: "msg_1"
        )
        let headers = context.headers
        #expect(headers["x-opencode-session-id"] == "ses_abc")
        #expect(headers["x-opencode-session"] == "ses_abc")
        #expect(headers["x-opencode-project"] == "0123456789abcdef0123456789abcdef01234567")
        #expect(headers["x-opencode-request"] == "msg_1")
        #expect(headers["x-opencode-client"] == "desktop")
        #expect(headers["User-Agent"] == OpenCodeRequestContext.userAgent)
        #expect(headers["Authorization"] == "Bearer public")
        #expect(headers["x-opencode-parent-session-id"] == nil)
        #expect(headers["x-parent-session-id"] == nil)
        #expect(headers["x-session-affinity"] == nil)
        #expect(headers["X-Session-Id"] == nil)
    }

    @Test("Parent session headers appear only for child sessions")
    func parentHeaders() {
        let context = OpenCodeRequestContext(sessionID: "ses_child", parentSessionID: "ses_parent")
        #expect(context.affinity == "ses_child")
        #expect(context.headers["x-opencode-parent-session-id"] == "ses_parent")
        #expect(context.headers["x-parent-session-id"] == "ses_parent")
        #expect(context.headers["x-opencode-session"] == "ses_child")
    }

    @Test("Extra headers override the contract values")
    func additionalHeaders() {
        let context = OpenCodeRequestContext(
            sessionID: "ses_abc",
            additionalHeaders: ["x-opencode-client": "cli", "X-Trace": "1"]
        )
        #expect(context.headers["x-opencode-client"] == "cli")
        #expect(context.headers["X-Trace"] == "1")
    }

    @Test("Auto Free requests carry the OpenCode client headers")
    func autoFreeRequestsCarryHeaders() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenCodeHeaderRecordingProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        OpenCodeHeaderRecordingProtocol.reset()

        let client = MyCoderAutoFreeClient(session: session)
        let sessionID = OpenCodeRequestContext.sessionID(from: "chat-123")
        let projectID = try #require(OpenCodeRequestContext.projectID(fromPath: "/tmp/project"))
        let context = OpenCodeRequestContext(
            sessionID: sessionID,
            projectID: projectID,
            requestID: "msg_abc"
        )

        _ = try await client.listModels(context: context)
        let modelsRequest = try #require(OpenCodeHeaderRecordingProtocol.captured.first)
        #expect(modelsRequest.value(forHTTPHeaderField: "x-opencode-session-id") == sessionID)
        #expect(modelsRequest.value(forHTTPHeaderField: "x-opencode-client") == "desktop")
        #expect(modelsRequest.value(forHTTPHeaderField: "User-Agent") == OpenCodeRequestContext.userAgent)
        #expect(modelsRequest.value(forHTTPHeaderField: "Authorization") == "Bearer public")
        #expect(modelsRequest.value(forHTTPHeaderField: "x-opencode-project") == projectID)

        for try await _ in client.chatCompletion(
            messages: [.init(role: "user", content: "hi")],
            context: context
        ) {}
        let chatRequest = try #require(OpenCodeHeaderRecordingProtocol.captured.last)
        #expect(chatRequest.value(forHTTPHeaderField: "x-opencode-session-id") == sessionID)
        #expect(chatRequest.value(forHTTPHeaderField: "x-opencode-session") == sessionID)
        #expect(chatRequest.value(forHTTPHeaderField: "x-opencode-request") == "msg_abc")
        #expect(chatRequest.value(forHTTPHeaderField: "x-opencode-project") == projectID)
        #expect(chatRequest.value(forHTTPHeaderField: "x-opencode-client") == "desktop")
        #expect(chatRequest.value(forHTTPHeaderField: "User-Agent") == OpenCodeRequestContext.userAgent)
        #expect(chatRequest.value(forHTTPHeaderField: "Authorization") == "Bearer public")
        #expect(chatRequest.value(forHTTPHeaderField: "Accept") == "*/*")
    }
}

private final class OpenCodeHeaderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    var captured: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func reset() {
        lock.lock()
        requests.removeAll()
        lock.unlock()
    }
}

private final class OpenCodeHeaderRecordingProtocol: URLProtocol {
    private static let recorder = OpenCodeHeaderRecorder()

    static func reset() {
        recorder.reset()
    }

    static var captured: [URLRequest] {
        recorder.captured
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recorder.record(request)
        let body: String
        let contentType: String
        if request.url?.path.hasSuffix("/models") == true {
            body = #"{"data":[{"id":"big-pickle"}]}"#
            contentType = "application/json"
        } else {
            body = "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n"
            contentType = "text/event-stream"
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
