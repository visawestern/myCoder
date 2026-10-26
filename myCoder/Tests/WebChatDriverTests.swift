import Testing
import Foundation
@testable import myCoder

@Suite("Web chat driver — agentic loop over web chat (plan Раздел 12 Блок 2/3)")
struct WebChatDriverTests {

    /// Scripted browser: returns queued responses for readText, records actions.
    final class FakeBridge: BrowserAutomationBridge, @unchecked Sendable {
        var responses: [String]           // successive response-container texts
        var responseIndex = -1            // advances to 0 on the first send
        var url = "https://kimi.com/chat"
        var pageTextValue = "chat ready"
        var evaluateValue: Any?
        var hasInput = true
        var hasSendButton = true
        var stopButtonVisible = false
        var typed: [String] = []
        var clicks = 0
        var cookiesValue: [BrowserCookie] = []
        var navigations = 0
        var captchaAfterSubmit = false
        var captchaWaitsUntilResolved = 1
        private var captchaWaits = 0
        private var pageTextReads = 0
        private var captchaResolved = false

        init(responses: [String]) { self.responses = responses }

        func navigate(to url: String) async throws { self.url = url; navigations += 1 }
        func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws { typed.append(text) }
        func click(selector: String) async throws {
            clicks += 1
            // Each send (click) yields the next scripted response.
            if responseIndex < responses.count - 1 { responseIndex += 1 }
        }
        func readText(selector: String) async throws -> String {
            // Before the first click the page has no assistant answer yet.
            // After submit, expose the scripted response selected by click().
            guard !responses.isEmpty, responseIndex >= 0 else { return "" }
            let idx = min(responseIndex, responses.count - 1)
            return responses[idx]
        }
        func responseFingerprint(selector: String) async throws -> String {
            responseIndex < 0 ? "" : "response-\(responseIndex)-click-\(clicks)"
        }
        func exists(selector: String) async throws -> Bool {
            if selector.contains("stop") || selector.contains("top") { return stopButtonVisible }
            if selector.contains("send") { return hasSendButton }
            // Option selectors (model/effort dropdown items) only "exist" if they
            // reference a model/effort that is in the scripted responses. This
            // prevents injection from advancing the response index in tests.
            if selector.contains("option") || selector.contains("has-text") {
                return responses.contains { response in
                    selector.contains(response) || selector.lowercased().contains(response.lowercased())
                }
            }
            return hasInput
        }
        func pageText() async throws -> String {
            pageTextReads += 1
            if captchaAfterSubmit, !captchaResolved, pageTextReads >= 3 {
                pageTextValue = "Please verify you are human"
            }
            return pageTextValue
        }
        func currentURL() async throws -> String { url }
        func evaluateJS(_ script: String) async throws -> Any? { evaluateValue }
        func cookies() async throws -> [BrowserCookie] { cookiesValue }
        func setCookies(_ cookies: [BrowserCookie]) async throws { cookiesValue = cookies }
        func screenshot(selector: String?) async throws -> Data { Data("png".utf8) }
        func wait(ms: Int) async {
            guard captchaAfterSubmit,
                  pageTextValue.localizedCaseInsensitiveContains("verify") else { return }
            captchaWaits += 1
            if captchaWaits >= captchaWaitsUntilResolved {
                captchaResolved = true
                pageTextValue = "chat ready"
                responses = ["done"]
                responseIndex = 0
            }
        }
    }

    final class RecordingExecutor: WebToolExecutor, @unchecked Sendable {
        var executed: [WebToolCall] = []
        var resultFor: (WebToolCall) -> String
        init(resultFor: @escaping (WebToolCall) -> String = { _ in "OK" }) { self.resultFor = resultFor }
        func execute(_ call: WebToolCall) async -> String {
            executed.append(call)
            return resultFor(call)
        }
        func execute(_ call: WebToolCall, userApproved: Bool) async -> String {
            await execute(call)
        }
    }

    private let selectors = WebVendorSelectors(
        input: "textarea", sendButton: "button.send",
        responseContainer: "div.response", stopButton: "button.stop"
    )

    private func makeDriver(bridge: FakeBridge, executor: WebToolExecutor) -> WebChatDriver {
        var driver = WebChatDriver(
            bridge: bridge, executor: executor, selectors: selectors,
            config: WebProviderConfig(vendor: .kimi, toolCallDelayMs: 0, acknowledgedToS: true),
            projectRoot: "/proj",
            accessLevel: .askBeforeChanges
        )
        // Disable model/effort injection in tests — the fake bridge has no real
        // web UI, and injection clicks would advance the scripted response index.
        driver.injectModelAndEffortEnabled = false
        driver.randomUnit = { 0.5 }
        driver.pollIntervalMs = 0
        driver.stabilityChecks = 1
        return driver
    }

    @Test("Kimi resolves active chat identity from DOM when URL has no /chat/ UUID")
    func kimiResolvesDomChatIdentityWithoutRouteUUID() async throws {
        let bridge = FakeBridge(responses: ["done"])
        bridge.url = "https://www.kimi.com/"
        bridge.evaluateValue = ["kimi-chat-uuid-1234"]
        let driver = makeDriver(bridge: bridge, executor: RecordingExecutor())

        #expect(try await driver.getCurrentChatID() == "kimi-chat-uuid-1234")
    }

    @Test func finalAnswerWithNoToolCallEmitsFinal() async {
        let bridge = FakeBridge(responses: ["The answer is 42."])
        let exec = RecordingExecutor()
        let driver = makeDriver(bridge: bridge, executor: exec)

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hi", isFirstMessage: false) { events.append($0) }

        #expect(events.contains(.final("The answer is 42.")))
        #expect(exec.executed.isEmpty)
    }

    @Test func toolCallRoundTripExecutesAndContinues() async {
        // 1st response: model asks to read a file. 2nd: final answer.
        let bridge = FakeBridge(responses: [
            "```tool\n{\"name\": \"read_file\", \"args\": {\"path\": \"a.txt\"}}\n```",
            "File says hello. Done."
        ])
        let exec = RecordingExecutor { _ in "hello" }
        let driver = makeDriver(bridge: bridge, executor: exec)

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "read a.txt", isFirstMessage: false) { events.append($0) }

        #expect(exec.executed.count == 1)
        #expect(exec.executed.first?.name == "read_file")
        #expect(events.contains(.toolResult(name: "read_file", result: "hello")))
        #expect(events.contains(.final("File says hello. Done.")))
    }

    @Test func firstMessagePrependsPreamble() async {
        let bridge = FakeBridge(responses: ["done"])
        let exec = RecordingExecutor()
        let driver = makeDriver(bridge: bridge, executor: exec)
        await driver.runTurn(userMessage: "task", isFirstMessage: true) { _ in }
        // First typed text must contain the tool preamble + the user message.
        #expect(bridge.typed.first?.contains("```tool") == true)
        #expect(bridge.typed.first?.contains("task") == true)
    }

    @Test func captchaInterruptsWithScreenshot() async {
        let bridge = FakeBridge(responses: ["irrelevant"])
        bridge.pageTextValue = "Please verify you are human"
        let exec = RecordingExecutor()
        let driver = makeDriver(bridge: bridge, executor: exec)

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hi", isFirstMessage: false) { events.append($0) }

        let hasCaptcha = events.contains { if case .captchaDetected = $0 { return true }; return false }
        #expect(hasCaptcha)
        #expect(exec.executed.isEmpty)   // stopped before executing anything
    }

    @Test func captchaDuringResponsePollingPausesAndResumes() async {
        let bridge = FakeBridge(responses: [""])
        bridge.captchaAfterSubmit = true
        bridge.captchaWaitsUntilResolved = 1
        let driver = makeDriver(bridge: bridge, executor: RecordingExecutor())

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hi", isFirstMessage: false) { events.append($0) }

        #expect(events.contains { if case .captchaDetected = $0 { return true }; return false })
        #expect(events.contains(.final("done")))
        #expect(bridge.typed.count == 1)
        #expect(bridge.clicks == 1)
    }

    @Test func loggedOutInterrupts() async {
        let bridge = FakeBridge(responses: ["x"])
        bridge.url = "https://chatgpt.com/auth/login"
        bridge.hasInput = false
        let driver = makeDriver(bridge: bridge, executor: RecordingExecutor())

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hi", isFirstMessage: false) { events.append($0) }
        #expect(events.contains(.loggedOut))
    }

    @Test("missing send button fails after typing (button materializes on input)")
    func missingSendButtonFailsBeforeTyping() async {
        // Audit 2026-09-09 (ChatGPT live): the send button materializes
        // only AFTER text lands in the composer, so the driver types first
        // and then waits boundedly for the button (FallbackRouter order).
        let bridge = FakeBridge(responses: ["x"])
        bridge.hasSendButton = false
        // Script an explicitly DISABLED send button: evaluateJS is what the
        // enabled-wait probes (a nil evaluation counts as ready).
        bridge.evaluateValue = false
        var driver = makeDriver(bridge: bridge, executor: RecordingExecutor())
        driver.sendEnabledTimeoutMs = 50

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hi", isFirstMessage: false) { events.append($0) }
        #expect(bridge.typed == ["hi"])
        #expect(events.contains { event in
            if case .error(let message) = event {
                return message.contains("button.send")
            }
            return false
        })
    }

    @Test("logged-out state is checked before model injection")
    func loggedOutPreflightBeatsInjectionFailure() async {
        let bridge = FakeBridge(responses: ["x"])
        bridge.url = "https://chatgpt.com/auth/login"
        bridge.hasInput = false
        let driver = WebChatDriver(
            bridge: bridge,
            executor: RecordingExecutor(),
            selectors: selectors,
            config: WebProviderConfig(
                vendor: .kimi,
                selectedModel: "k2",
                acknowledgedToS: true
            ),
            projectRoot: "/proj",
            accessLevel: .askBeforeChanges,
            pollIntervalMs: 0,
            stabilityChecks: 1
        )

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hi", isFirstMessage: false) { events.append($0) }
        #expect(events.contains(.loggedOut))
        #expect(!events.contains { event in
            if case .modelInjectionFailed = event { return true }
            return false
        })
        #expect(bridge.typed.isEmpty)
    }

    @Test func iterationLimitStopsRunawayLoop() async {
        // Distinct calls defeat the idle detector → the iteration cap stops it.
        let bridge = FakeBridge(responses: [
            "```tool\n{\"name\": \"list_dir\", \"args\": {\"path\": \".\"}}\n```",
            "```tool\n{\"name\": \"list_dir\", \"args\": {\"path\": \"src\"}}\n```",
            "```tool\n{\"name\": \"list_dir\", \"args\": {\"path\": \"docs\"}}\n```",
            "```tool\n{\"name\": \"list_dir\", \"args\": {\"path\": \"tests\"}}\n```",
        ])
        let exec = RecordingExecutor { _ in "[]" }
        var driver = makeDriver(bridge: bridge, executor: exec)
        driver = WebChatDriver(
            bridge: bridge, executor: exec, selectors: selectors,
            config: WebProviderConfig(vendor: .kimi, toolCallDelayMs: 0, maxToolIterations: 3, acknowledgedToS: true),
            projectRoot: "/proj",
            accessLevel: .askBeforeChanges,
            randomUnit: { 0.5 }, pollIntervalMs: 0, stabilityChecks: 1
        )
        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "loop", isFirstMessage: false) { events.append($0) }
        #expect(events.contains(.iterationLimitReached))
        #expect(exec.executed.count <= 3)
    }

    @Test func identicalRepeatsStopViaIdleBeforeIterationCap() async {
        // Identical repeats trip the idle killer (C3) instead of burning
        // the whole iteration budget — earlier and more honest.
        let bridge = FakeBridge(responses: ["```tool\n{\"name\": \"list_dir\", \"args\": {\"path\": \".\"}}\n```"])
        let exec = RecordingExecutor { _ in "[]" }
        let driver = makeDriver(bridge: bridge, executor: exec)
        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "loop", isFirstMessage: false) { events.append($0) }
        #expect(events.contains { if case .idleLoopStopped = $0 { return true }; return false })
        #expect(!events.contains(.iterationLimitReached))
    }

    @Test func invalidToolPathReturnsValidationErrorNotExecution() async {
        let bridge = FakeBridge(responses: [
            "```tool\n{\"name\": \"read_file\", \"args\": {\"path\": \"../../etc/passwd\"}}\n```",
            "stopped."
        ])
        let exec = RecordingExecutor()
        let driver = makeDriver(bridge: bridge, executor: exec)
        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hack", isFirstMessage: false) { events.append($0) }
        // Executor never runs the escaping path; a validation error is fed back.
        #expect(exec.executed.isEmpty)
        let hasValidationResult = events.contains { e in
            if case .toolResult(_, let r) = e { return r.contains("validation error") }
            return false
        }
        #expect(hasValidationResult)
    }

    @Test func sessionLimitTriggersRestartWithCarryOver() async {
        // 1st response: Kimi length-limit notice. 2nd (after restart): final.
        let bridge = FakeBridge(responses: [
            "Your conversation with Kimi is getting too long. Try starting a new session.",
            "Continuing. Done."
        ])
        let exec = RecordingExecutor()
        let driver = makeDriver(bridge: bridge, executor: exec)

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hi", isFirstMessage: false) { events.append($0) }

        #expect(events.contains(.sessionLimitReached))
        #expect(events.contains(.sessionRestarted))
        #expect(bridge.navigations >= 1)          // navigated to a fresh chat
        #expect(events.contains(.final("Continuing. Done.")))
    }

    @Test func largeFirstMessageIsSplitIntoParts() async {
        let bridge = FakeBridge(responses: ["ok done"])
        let exec = RecordingExecutor()
        let driver = makeDriver(bridge: bridge, executor: exec)
        // A prompt well over the chunk budget forces a split.
        let big = Array(repeating: "This is a sentence about the task.", count: 400).joined(separator: "\n\n")

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: big, isFirstMessage: true) { events.append($0) }

        let split = events.contains { if case .promptSplit = $0 { return true }; return false }
        #expect(split)
        // More than one message was typed for the single user turn.
        #expect(bridge.typed.count > 1)
        // Exactly one message carries the numbered FINAL PART header (the literal
        // "FINAL PART N/N" in the preamble instruction is not numbered).
        let numberedFinal = bridge.typed.filter { msg in
            msg.range(of: "FINAL PART [0-9]+/[0-9]+", options: .regularExpression) != nil
        }
        #expect(numberedFinal.count == 1)
    }

    @Test("idle loop stops before the third identical tool call executes")
    func idleLoopStopsOnRepeat() async {
        let toolBlock = "```tool\n{\"name\": \"list_dir\", \"args\": {\"path\": \".\"}}\n```"
        let bridge = FakeBridge(responses: [toolBlock])
        let exec = RecordingExecutor { _ in "contents" }
        let driver = makeDriver(bridge: bridge, executor: exec)

        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "list", isFirstMessage: false) { events.append($0) }

        #expect(events.contains { if case .idleLoopStopped = $0 { return true }; return false })
        #expect(exec.executed.count == 2)
        #expect(!events.contains { if case .final = $0 { return true }; return false })
    }
}

@Suite("Web session manager — cookie persistence (plan Раздел 12 Блок 3)")
struct WebSessionManagerTests {

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-websess-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func persistAndRestoreRoundTrip() throws {
        let home = try makeTempHome()
        let store = WebSessionStore(
            cookies: [BrowserCookie(name: "sid", value: "abc", domain: "kimi.com", expiresEpoch: 9_999_999_999)],
            localStorage: ["theme": "dark"], savedAt: Date()
        )
        try WebSessionManager.persist(store, providerId: "p1", homeDirectory: home)
        let restored = WebSessionManager.restore(providerId: "p1", homeDirectory: home)
        #expect(restored?.cookies.first?.value == "abc")
        #expect(restored?.localStorage["theme"] == "dark")
    }

    @Test func restoreReturnsNilWhenAbsent() throws {
        let home = try makeTempHome()
        #expect(WebSessionManager.restore(providerId: "none", homeDirectory: home) == nil)
    }

    @Test func clearRemovesStore() throws {
        let home = try makeTempHome()
        let store = WebSessionStore(cookies: [], localStorage: [:], savedAt: Date())
        try WebSessionManager.persist(store, providerId: "p2", homeDirectory: home)
        try WebSessionManager.clear(providerId: "p2", homeDirectory: home)
        #expect(WebSessionManager.restore(providerId: "p2", homeDirectory: home) == nil)
    }

    @Test func expiredWhenAllCookiesPast() {
        let store = WebSessionStore(
            cookies: [BrowserCookie(name: "s", value: "v", domain: "d", expiresEpoch: 100)],
            localStorage: [:], savedAt: Date(timeIntervalSince1970: 50)
        )
        #expect(WebSessionManager.isExpired(store, now: Date(timeIntervalSince1970: 200)))
        #expect(!WebSessionManager.isExpired(store, now: Date(timeIntervalSince1970: 50)))
    }
}


@Suite("WEB-CHAT-12: approval interruption in web agent loop")
struct WebChatApprovalInterruptionTests {
    final class ApprovalBridge: BrowserAutomationBridge, @unchecked Sendable {
        var typed: [String] = []
        var submitted = false

        func navigate(to url: String) async throws {}
        func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws { typed.append(text) }
        func click(selector: String) async throws { submitted = true }
        func readText(selector: String) async throws -> String {
            submitted ? "```tool\n{\"name\":\"write_file\",\"args\":{\"path\":\"a.txt\",\"content\":\"x\"}}\n```" : ""
        }
        func responseFingerprint(selector: String) async throws -> String { submitted ? "submitted" : "" }
        func exists(selector: String) async throws -> Bool { selector.contains("stop") ? false : true }
        func pageText() async throws -> String { "chat ready" }
        func currentURL() async throws -> String { "https://kimi.com/chat" }
        func cookies() async throws -> [BrowserCookie] { [] }
        func setCookies(_ cookies: [BrowserCookie]) async throws {}
        func screenshot(selector: String?) async throws -> Data { Data() }
        func wait(ms: Int) async {}
    }

    struct RecordingExecutor: WebToolExecutor {
        var calls = LockedCalls()
        func execute(_ call: WebToolCall) async -> String {
            calls.append(call)
            return "should not execute"
        }
        func execute(_ call: WebToolCall, userApproved: Bool) async -> String {
            await execute(call)
        }
    }

    final class LockedCalls: @unchecked Sendable {
        private var storage: [WebToolCall] = []
        private let lock = NSLock()
        func append(_ call: WebToolCall) { lock.lock(); storage.append(call); lock.unlock() }
        func snapshot() -> [WebToolCall] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    @Test("ask-before-changes: gated tool is not executed and the model receives an honest decline")
    func mutationIsBlockedBeforeExecution() async {
        let bridge = ApprovalBridge()
        let calls = LockedCalls()
        let executor = ClosureWebToolExecutor { call in
            calls.append(call)
            return "should not execute"
        }
        // approvalBox == nil (unit-test default): the driver auto-declines the
        // gated call after a zero-second wait and feeds the decline back to
        // the model instead of executing it.
        let driver = WebChatDriver(
            bridge: bridge,
            executor: executor,
            selectors: WebVendorSelectors(input: "textarea", sendButton: "button.send", responseContainer: "div.response", stopButton: "button.stop"),
            config: WebProviderConfig(vendor: .kimi, maxToolIterations: 3, acknowledgedToS: true),
            projectRoot: "/tmp",
            accessLevel: .askBeforeChanges,
            pollIntervalMs: 0,
            stabilityChecks: 1,
            injectModelAndEffortEnabled: false,
            approvalWaitSeconds: 0
        )
        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "edit", isFirstMessage: false) { events.append($0) }
        #expect(calls.snapshot().isEmpty)
        // The approval request was surfaced (the interactive card's event),
        // the tool itself was never executed, and the model received the
        // honest decline as a tool_result.
        #expect(events.contains { event in
            if case .approvalRequest(let request) = event { return request.tool == "write_file" }
            return false
        })
        #expect(events.contains { event in
            if case .toolResult(let name, let result) = event {
                return name == "write_file" && result.contains("declined")
            }
            return false
        })
    }

    struct ClosureWebToolExecutor: WebToolExecutor {
        let body: (WebToolCall) async -> String
        func execute(_ call: WebToolCall) async -> String { await body(call) }
        func execute(_ call: WebToolCall, userApproved: Bool) async -> String { await body(call) }
    }
}
