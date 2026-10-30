import Testing
import Foundation
@testable import myCoder

@Suite("Auto Free proxy rotation", .serialized)
struct AutoFreeProxyTests {

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "com.mycoder.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Parsing

    @Test func parsesSupportedSchemes() throws {
        let http = try AutoFreeProxy.parse("http://192.168.1.10:8080")
        #expect(http.scheme == "http")
        #expect(http.host == "192.168.1.10")
        #expect(http.port == 8080)
        #expect(http.isEnabled)

        let socks = try AutoFreeProxy.parse("socks5://127.0.0.1:1080")
        #expect(socks.scheme == "socks5")
        #expect(socks.urlString == "socks5://127.0.0.1:1080")

        let https = try AutoFreeProxy.parse("https://proxy.example.com:8443")
        #expect(https.scheme == "https")
    }

    @Test func bareHostPortDefaultsToHTTP() throws {
        let proxy = try AutoFreeProxy.parse("  10.0.0.5:3128  ")
        #expect(proxy.scheme == "http")
        #expect(proxy.host == "10.0.0.5")
        #expect(proxy.port == 3128)
    }

    @Test func rejectsInvalidAddresses() {
        #expect(throws: AutoFreeProxyValidationError.empty) { try AutoFreeProxy.parse("   ") }
        #expect(throws: AutoFreeProxyValidationError.unsupportedScheme("ftp")) {
            try AutoFreeProxy.parse("ftp://host:21")
        }
        #expect(throws: AutoFreeProxyValidationError.invalidPort) {
            try AutoFreeProxy.parse("http://host")
        }
        #expect(throws: AutoFreeProxyValidationError.invalidPort) {
            try AutoFreeProxy.parse("http://host:70000")
        }
        #expect(throws: AutoFreeProxyValidationError.credentialsUnsupported) {
            try AutoFreeProxy.parse("http://user:secret@host:8080")
        }
        #expect(throws: AutoFreeProxyValidationError.malformedURL) {
            try AutoFreeProxy.parse("http://host:8080/some/path")
        }
    }

    @Test func proxySettingsUseTheSessionDictionaryKeys() throws {
        let socks = try AutoFreeProxy.parse("socks5://127.0.0.1:1080")
        #expect(socks.connectionProxySettings["SOCKSEnable"] as? Int == 1)
        #expect(socks.connectionProxySettings["SOCKSProxy"] as? String == "127.0.0.1")
        #expect(socks.connectionProxySettings["SOCKSPort"] as? Int == 1080)

        let http = try AutoFreeProxy.parse("http://proxy.local:8080")
        #expect(http.connectionProxySettings["HTTPProxy"] as? String == "proxy.local")
        #expect(http.connectionProxySettings["HTTPSProxy"] as? String == "proxy.local")
        #expect(http.connectionProxySettings["HTTPSPort"] as? Int == 8080)
    }

    // MARK: - Rotation

    @Test func rotationStartsAtCursorAndWraps() throws {
        let first = try AutoFreeProxy.parse("http://a:1")
        let second = try AutoFreeProxy.parse("http://b:2")
        let third = try AutoFreeProxy.parse("http://c:3")
        let list = [first, second, third]

        #expect(AutoFreeProxyRotation.order(list, cursor: 0).map(\.host) == ["a", "b", "c"])
        #expect(AutoFreeProxyRotation.order(list, cursor: 1).map(\.host) == ["b", "c", "a"])
        #expect(AutoFreeProxyRotation.order(list, cursor: 3).map(\.host) == ["a", "b", "c"])
        #expect(AutoFreeProxyRotation.order([], cursor: 0).isEmpty)
    }

    @Test func cursorAdvancesByTheAttemptedCount() {
        #expect(AutoFreeProxyRotation.advancedCursor(0, attempted: 1, count: 3) == 1)
        #expect(AutoFreeProxyRotation.advancedCursor(2, attempted: 1, count: 3) == 0)
        #expect(AutoFreeProxyRotation.advancedCursor(1, attempted: 2, count: 3) == 0)
        #expect(AutoFreeProxyRotation.advancedCursor(0, attempted: 0, count: 3) == 0)
        #expect(AutoFreeProxyRotation.advancedCursor(0, attempted: 3, count: 0) == 0)
    }

    @Test func storePersistsTheListAndTheCursor() throws {
        let defaults = makeDefaults("auto-free-proxy-store")
        defer { defaults.removePersistentDomain(forName: "com.mycoder.tests.auto-free-proxy-store") }

        let store = AutoFreeProxyStore(defaults: defaults)
        try store.add("socks5://a:1080")
        try store.add("http://b:8080")

        let reloaded = AutoFreeProxyStore(defaults: defaults)
        #expect(reloaded.proxies.map(\.host) == ["a", "b"])

        reloaded.setEnabled(false, id: reloaded.proxies[0].id)
        #expect(reloaded.rotationOrder().map(\.host) == ["b"])

        reloaded.advanceRotation(attempted: 1)
        #expect(AutoFreeProxyStore(defaults: defaults).rotationOrder().map(\.host) == ["b"])
    }

    @Test func duplicateProxyIsRejected() throws {
        let defaults = makeDefaults("auto-free-proxy-duplicate")
        defer { defaults.removePersistentDomain(forName: "com.mycoder.tests.auto-free-proxy-duplicate") }

        let store = AutoFreeProxyStore(defaults: defaults)
        try store.add("socks5://a:1080")
        #expect(throws: AutoFreeProxyValidationError.duplicate) {
            try store.add("socks5://A:1080")
        }
        #expect(store.proxies.count == 1)
    }

    // MARK: - Error classification

    @Test func usageLimitIsProxyRetryableButIdentityGateIsNot() {
        let usage = MyCoderAutoFreeError.mapHttpError(
            statusCode: 429,
            body: #"{"error":{"type":"FreeUsageLimitError","message":"Free usage exceeded"}}"#,
            operation: "Free model streaming"
        )
        #expect(MyCoderAutoFreeClient.isRetryableLimit(usage, statusCode: 429))
        #expect(MyCoderAutoFreeClient.allowsProxyRetry(usage, statusCode: 429))

        let gate = MyCoderAutoFreeError.mapHttpError(
            statusCode: 403,
            body: #"{"error":{"type":"FreeTierError","message":"OpenCode's free tier can only be used from within OpenCode."}}"#,
            operation: "Free model streaming"
        )
        #expect(!MyCoderAutoFreeClient.isRetryableLimit(gate, statusCode: 403))
        #expect(!MyCoderAutoFreeClient.allowsProxyRetry(gate, statusCode: 403))

        let unavailable = MyCoderAutoFreeError.mapHttpError(
            statusCode: 503,
            body: "upstream down",
            operation: "Free model streaming"
        )
        #expect(MyCoderAutoFreeClient.isRetryableLimit(unavailable, statusCode: 503))
        #expect(!MyCoderAutoFreeClient.allowsProxyRetry(unavailable, statusCode: 503))
    }

    @Test func exhaustedUsageLimitPointsAtTheProxyRoute() {
        let error = MyCoderAutoFreeError.freeTierBlocked(
            "FreeUsageLimitError: Free usage exceeded, subscribe to Go"
        )
        let text = error.localizedDescription
        #expect(text.contains("rate-limit proxy"))
        #expect(!text.contains("Use OpenCode"))

        let gate = MyCoderAutoFreeError.freeTierBlocked(
            "FreeTierError: OpenCode's free tier can only be used from within OpenCode."
        )
        #expect(gate.localizedDescription.contains("Use OpenCode"))
    }

    // MARK: - Client integration

    @Test func rateLimitedTurnGoesStraightToTheFirstProxy() async throws {
        let defaults = makeDefaults("auto-free-proxy-client")
        defer { defaults.removePersistentDomain(forName: "com.mycoder.tests.auto-free-proxy-client") }
        let store = AutoFreeProxyStore(defaults: defaults)
        try store.add("socks5://127.0.0.1:1080")

        let direct = URLSession(configuration: proxyTestConfiguration(ProxyAlwaysLimitedProtocol.self))
        defer { direct.invalidateAndCancel() }
        let proxied = URLSession(configuration: proxyTestConfiguration(ProxyAlwaysOKProtocol.self))
        defer { proxied.invalidateAndCancel() }

        ProxyAlwaysLimitedProtocol.reset()
        ProxyAlwaysOKProtocol.reset()

        let client = MyCoderAutoFreeClient(
            session: direct,
            sessionDefaults: defaults,
            proxyStore: store,
            proxySessionFactory: { _ in proxied }
        )

        var text = ""
        for try await event in client.chatCompletion(
            messages: [.init(role: "user", content: "test")],
            context: OpenCodeRequestContext(sessionID: OpenCodeRequestContext.sessionID(from: "chat-proxy", defaults: defaults))
        ) {
            if case .content(let chunk) = event { text += chunk }
        }

        #expect(text == "ok")
        // One direct attempt, then the proxy immediately — no second direct
        // attempt from the same throttled IP.
        #expect(ProxyAlwaysLimitedProtocol.requestCount == 1)
        #expect(ProxyAlwaysOKProtocol.requestCount == 1)
    }

    @Test func limitedProxyRotatesToTheNextOne() async throws {
        let defaults = makeDefaults("auto-free-proxy-rotation-client")
        defer { defaults.removePersistentDomain(forName: "com.mycoder.tests.auto-free-proxy-rotation-client") }
        let store = AutoFreeProxyStore(defaults: defaults)
        try store.add("socks5://a:1080")
        try store.add("socks5://b:1080")
        try store.add("socks5://c:1080")

        let direct = URLSession(configuration: proxyTestConfiguration(ProxyAlwaysLimitedProtocol.self))
        defer { direct.invalidateAndCancel() }
        let limitedProxy = URLSession(configuration: proxyTestConfiguration(ProxyAlwaysLimitedProtocol.self))
        defer { limitedProxy.invalidateAndCancel() }
        let okProxy = URLSession(configuration: proxyTestConfiguration(ProxyAlwaysOKProtocol.self))
        defer { okProxy.invalidateAndCancel() }

        ProxyAlwaysLimitedProtocol.reset()
        ProxyAlwaysOKProtocol.reset()

        let client = MyCoderAutoFreeClient(
            session: direct,
            sessionDefaults: defaults,
            proxyStore: store,
            proxySessionFactory: { proxy in proxy.host == "a" ? limitedProxy : okProxy }
        )

        var text = ""
        for try await event in client.chatCompletion(
            messages: [.init(role: "user", content: "test")],
            context: OpenCodeRequestContext(sessionID: OpenCodeRequestContext.sessionID(from: "chat-proxy-rotate", defaults: defaults))
        ) {
            if case .content(let chunk) = event { text += chunk }
        }
        #expect(text == "ok")

        // 1 direct + proxy a (limited) + proxy b (served the turn).
        #expect(ProxyAlwaysLimitedProtocol.requestCount == 2)
        #expect(ProxyAlwaysOKProtocol.requestCount == 1)
        // Two proxies were attempted, so the next turn starts with proxy c.
        #expect(store.rotationOrder().map(\.host) == ["c", "a", "b"])
    }

    @Test func allLimitedProxiesReturnTheOriginalError() async throws {
        let defaults = makeDefaults("auto-free-proxy-all-limited")
        defer { defaults.removePersistentDomain(forName: "com.mycoder.tests.auto-free-proxy-all-limited") }
        let store = AutoFreeProxyStore(defaults: defaults)
        try store.add("socks5://a:1080")
        try store.add("socks5://b:1080")

        let direct = URLSession(configuration: proxyTestConfiguration(ProxyAlwaysLimitedProtocol.self))
        defer { direct.invalidateAndCancel() }
        let proxied = URLSession(configuration: proxyTestConfiguration(ProxyAlwaysLimitedProtocol.self))
        defer { proxied.invalidateAndCancel() }

        ProxyAlwaysLimitedProtocol.reset()
        let client = MyCoderAutoFreeClient(
            session: direct,
            sessionDefaults: defaults,
            proxyStore: store,
            proxySessionFactory: { _ in proxied }
        )

        do {
            for try await _ in client.chatCompletion(
                messages: [.init(role: "user", content: "test")],
                context: OpenCodeRequestContext(sessionID: OpenCodeRequestContext.sessionID(from: "chat-proxy-fail", defaults: defaults))
            ) {}
            Issue.record("Expected the original rate-limit error")
        } catch let error as MyCoderAutoFreeError {
            guard case .freeTierBlocked(let message) = error else {
                Issue.record("Expected the original free-usage error, got \(error)")
                return
            }
            #expect(message.contains("Free usage exceeded"))
            // Once every proxy is limited too, another model on the same
            // connection cannot help: the carousel must stop with this error.
            #expect(MyCoderAutoFreeClient.shouldHaltFailover(for: error))
        }

        // 1 direct + both proxies.
        #expect(ProxyAlwaysLimitedProtocol.requestCount == 3)
    }

    @Test func withoutProxiesTheSingleSessionRetryIsKept() async throws {
        let defaults = makeDefaults("auto-free-proxy-none")
        defer { defaults.removePersistentDomain(forName: "com.mycoder.tests.auto-free-proxy-none") }
        let store = AutoFreeProxyStore(defaults: defaults)

        let direct = URLSession(configuration: proxyTestConfiguration(ProxyLimitedThenOKProtocol.self))
        defer { direct.invalidateAndCancel() }
        ProxyLimitedThenOKProtocol.reset()

        let client = MyCoderAutoFreeClient(session: direct, sessionDefaults: defaults, proxyStore: store)
        var text = ""
        for try await event in client.chatCompletion(
            messages: [.init(role: "user", content: "test")],
            context: OpenCodeRequestContext(sessionID: OpenCodeRequestContext.sessionID(from: "chat-no-proxy", defaults: defaults))
        ) {
            if case .content(let chunk) = event { text += chunk }
        }
        #expect(text == "ok")
        #expect(ProxyLimitedThenOKProtocol.requestCount == 2)
    }

    private func proxyTestConfiguration(_ protocolClass: AnyClass) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return configuration
    }
}

private let limitedBody = #"{"error":{"type":"FreeUsageLimitError","message":"Free usage exceeded, subscribe to Go"}}"#
private let successBody = "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n"

private final class ProxyRequestCounter {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        count = 0
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class ProxyAlwaysLimitedProtocol: URLProtocol {
    static let counter = ProxyRequestCounter()
    static var requestCount: Int { counter.value }
    static func reset() { counter.reset() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        _ = Self.counter.increment()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(limitedBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ProxyAlwaysOKProtocol: URLProtocol {
    static let counter = ProxyRequestCounter()
    static var requestCount: Int { counter.value }
    static func reset() { counter.reset() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        _ = Self.counter.increment()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(successBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ProxyLimitedThenOKProtocol: URLProtocol {
    static let counter = ProxyRequestCounter()
    static var requestCount: Int { counter.value }
    static func reset() { counter.reset() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let attempt = Self.counter.increment()
        let status = attempt == 1 ? 429 : 200
        let body = attempt == 1 ? limitedBody : successBody
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": attempt == 1 ? "application/json" : "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}