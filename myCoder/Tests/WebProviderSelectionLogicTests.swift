import Foundation
import Testing
@testable import myCoder

@Suite("Web provider selection and send contract")
struct WebProviderSelectionLogicTests {
    @Test("Selecting a web model updates the persisted config value")
    func selectingModelUsesOneSourceOfTruth() {
        let config = WebProviderConfig(
            vendor: .kimi,
            selectedModel: "k2",
            discoveredModels: [WebProviderModel(name: "k2"), WebProviderModel(name: "k2-thinking")]
        )
        let updated = WebProviderSelectionLogic.selectingModel(
            "k2-thinking",
            in: config,
            availableModels: ["k2", "k2-thinking"]
        )
        #expect(updated.selectedModel == "k2-thinking")
    }

    @Test("switching provider prefers its persisted model over a global legacy selection")
    func providerSwitchUsesProviderSelection() {
        let config = WebProviderConfig(
            vendor: .kimi,
            selectedModel: "kimi-thinking",
            discoveredModels: [
                WebProviderModel(name: "shared-model"),
                WebProviderModel(name: "kimi-thinking")
            ]
        )
        #expect(WebProviderSelectionLogic.modelForProviderSwitch(
            config: config,
            globalSelectedModel: "shared-model",
            availableModels: ["shared-model", "kimi-thinking"]
        ) == "kimi-thinking")
    }

    @Test("Unknown web model cannot silently replace the selected model")
    func selectingUnknownModelIsIgnored() {
        let config = WebProviderConfig(vendor: .qwen, selectedModel: "qwen-plus")
        let updated = WebProviderSelectionLogic.selectingModel(
            "not-in-menu",
            in: config,
            availableModels: ["qwen-plus"]
        )
        #expect(updated.selectedModel == "qwen-plus")
    }

    @Test("An empty live model snapshot never returns a stale persisted model")
    func emptyLiveSnapshotClearsEffectiveModel() {
        let config = WebProviderConfig(
            vendor: .chatgpt,
            selectedModel: "gpt-stale",
            discoveredModels: [WebProviderModel(name: "gpt-stale")]
        )
        #expect(WebProviderSelectionLogic.selectedModel(for: config, availableModels: []) == "")
        #expect(WebProviderSelectionLogic.effectiveSelectedModel(for: config, availableModels: []) == "")
    }

    @Test("Web providers hide effort menu before live discovery")
    func effortMenuIsHiddenBeforeDiscovery() {
        for vendor in [WebChatVendor.kimi, .qwen, .chatgpt, .custom] {
            let config = WebProviderConfig(vendor: vendor)
            #expect(WebProviderSelectionLogic.availableEfforts(for: config).isEmpty)
        }
    }

    @Test("Effort capabilities follow the effective model when persisted selection is stale")
    func effortCapabilitiesFollowEffectiveModel() {
        let config = WebProviderConfig(
            vendor: .qwen,
            selectedModel: "removed-model",
            discoveredModels: [
                WebProviderModel(name: "live-model", availableEfforts: [.high])
            ]
        )
        let effective = WebProviderSelectionLogic.effectiveSelectedModel(for: config)
        #expect(effective == "live-model")
        #expect(WebProviderSelectionLogic.availableEfforts(for: config, modelID: effective) == [.high])
    }

    @Test("A manually added model does not inherit another model's effort capabilities")
    func effortCapabilitiesDoNotLeakAcrossModels() {
        let config = WebProviderConfig(
            vendor: .qwen,
            selectedModel: "manual-model",
            discoveredModels: [
                WebProviderModel(name: "live-model", availableEfforts: [.high])
            ],
            manuallyAddedModels: ["manual-model"],
            discoveredEffortLevels: [.high]
        )
        #expect(WebProviderSelectionLogic.availableEfforts(for: config, modelID: "manual-model").isEmpty)
    }

    @Test("Selecting web effort updates only the web provider config")
    func selectingEffortUsesConfig() {
        let config = WebProviderConfig(
            vendor: .qwen,
            effort: .medium,
            discoveredEffortLevels: WebEffort.allCases
        )
        let updated = WebProviderSelectionLogic.selectingEffort(.high, in: config)
        #expect(updated.effort == .high)
    }
}

@Suite("Web driver model and effort guard")
struct WebDriverSelectionGuardTests {
    final class InjectionBridge: BrowserAutomationBridge, @unchecked Sendable {
        var typed: [String] = []
        var sendClicks = 0
        var menuClicks = 0
        var clickedSelectors: [String] = []
        var submitted = false
        let acceptsOption: Bool

        init(acceptsOption: Bool) { self.acceptsOption = acceptsOption }

        func navigate(to url: String) async throws {}
        func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws { typed.append(text) }
        func click(selector: String) async throws {
            menuClicks += 1
            clickedSelectors.append(selector)
            if selector.contains("send") {
                sendClicks += 1
                submitted = true
            }
        }
        func clickByText(selector: String, text: String) async throws -> Bool { acceptsOption }
        func readText(selector: String) async throws -> String { submitted ? "final answer" : "" }
        func responseFingerprint(selector: String) async throws -> String { submitted ? "submitted-1" : "" }
        func exists(selector: String) async throws -> Bool {
            if selector.contains("stop") { return !submitted }
            return true
        }
        func pageText() async throws -> String { "chat ready" }
        func currentURL() async throws -> String { "https://kimi.com/chat" }
        func cookies() async throws -> [BrowserCookie] { [] }
        func setCookies(_ cookies: [BrowserCookie]) async throws {}
        func screenshot(selector: String?) async throws -> Data { Data() }
        func wait(ms: Int) async {}
    }

    struct NoopExecutor: WebToolExecutor {
        func execute(_ call: WebToolCall) async -> String { "ok" }
        func execute(_ call: WebToolCall, userApproved: Bool) async -> String { "ok" }
    }

    private let selectors = WebVendorSelectors(
        input: "textarea",
        sendButton: "button.send",
        responseContainer: "div.response",
        stopButton: "button.stop"
    )

    @Test("A failed model or effort injection reports status and blocks duplicate send")
    func failedModelInjectionBlocksSendUntilRefresh() async {
        let bridge = InjectionBridge(acceptsOption: false)
        let driver = WebChatDriver(
            bridge: bridge,
            executor: NoopExecutor(),
            selectors: selectors,
            config: WebProviderConfig(vendor: .kimi, selectedModel: "missing-model", effort: .high),
            projectRoot: "/tmp",
            accessLevel: .askBeforeChanges,
            pollIntervalMs: 0,
            stabilityChecks: 1
        )
        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hello", isFirstMessage: false) { events.append($0) }
        #expect(bridge.typed.count == 0)
        #expect(bridge.sendClicks == 0)
        #expect(events.contains { event in
            if case .modelInjectionFailed = event { return true }
            return false
        })
        #expect(events.contains { event in
            if case .effortInjectionFailed = event { return true }
            return false
        })
        #expect(!events.contains { event in
            if case .error = event { return true }
            return false
        })
    }

    @Test("An undetected model does not receive a global effort injection")
    func undetectedModelSkipsEffortInjection() async {
        let bridge = InjectionBridge(acceptsOption: true)
        let driver = WebChatDriver(
            bridge: bridge,
            executor: NoopExecutor(),
            selectors: selectors,
            config: WebProviderConfig(
                vendor: .kimi,
                selectedModel: "manual-model",
                effort: .high,
                discoveredModels: [WebProviderModel(name: "live-model", availableEfforts: [.high])]
            ),
            projectRoot: "/tmp",
            accessLevel: .askBeforeChanges,
            pollIntervalMs: 0,
            stabilityChecks: 1
        )
        await driver.runTurn(userMessage: "hello", isFirstMessage: false) { _ in }
        #expect(!bridge.clickedSelectors.contains("div.effort-item"))
    }

    @Test("Catalog keeps model and effort controls separate")
    func modelAndEffortUseIndependentCatalogSelectors() async {
        let bridge = InjectionBridge(acceptsOption: true)
        let driver = WebChatDriver(
            bridge: bridge,
            executor: NoopExecutor(),
            selectors: selectors,
            config: WebProviderConfig(vendor: .kimi, selectedModel: "k2", effort: .high),
            projectRoot: "/tmp",
            accessLevel: .askBeforeChanges,
            pollIntervalMs: 0,
            stabilityChecks: 1
        )
        await driver.runTurn(userMessage: "hello", isFirstMessage: false) { _ in }
        #expect(bridge.clickedSelectors.first == ".current-model")
        #expect(bridge.clickedSelectors.contains(".effort-item .effort-current"))
        #expect(bridge.clickedSelectors.last == "button.send")
    }

    @Test("A confirmed model and effort are injected before send")
    func successfulInjectionPrecedesSend() async {
        let bridge = InjectionBridge(acceptsOption: true)
        let driver = WebChatDriver(
            bridge: bridge,
            executor: NoopExecutor(),
            selectors: selectors,
            config: WebProviderConfig(vendor: .kimi, selectedModel: "k2", effort: .high),
            projectRoot: "/tmp",
            accessLevel: .askBeforeChanges,
            pollIntervalMs: 0,
            stabilityChecks: 1
        )
        await driver.runTurn(userMessage: "hello", isFirstMessage: false) { _ in }
        #expect(bridge.typed.count == 1)
        #expect(bridge.sendClicks == 1)
    }

    @Test("A failed model confirmation blocks send even when the model has no effort control")
    func failedModelOnlyInjectionBlocksSend() async {
        let bridge = InjectionBridge(acceptsOption: false)
        let config = WebProviderConfig(
            vendor: .kimi,
            selectedModel: "model-without-effort",
            discoveredModels: [WebProviderModel(name: "model-without-effort", availableEfforts: [])]
        )
        let driver = WebChatDriver(
            bridge: bridge,
            executor: NoopExecutor(),
            selectors: selectors,
            config: config,
            projectRoot: "/tmp",
            accessLevel: .askBeforeChanges,
            pollIntervalMs: 0,
            stabilityChecks: 1
        )
        var events: [WebChatEvent] = []
        await driver.runTurn(userMessage: "hello", isFirstMessage: false) { events.append($0) }
        #expect(bridge.typed.isEmpty)
        #expect(bridge.sendClicks == 0)
        #expect(events.contains { event in
            if case .modelInjectionFailed = event { return true }
            return false
        })
        }
    @Test("Custom vendor uses its persisted model selector when no bundled catalog entry exists")
    func customVendorUsesCustomModelSelector() async {
        let bridge = InjectionBridge(acceptsOption: true)
        let config = WebProviderConfig(
            vendor: .custom,
            selectedModel: "custom-model",
            customModelSelector: ".custom-model"
        )
        let driver = WebChatDriver(
            bridge: bridge,
            executor: NoopExecutor(),
            selectors: selectors,
            config: config,
            projectRoot: "/tmp",
            accessLevel: .askBeforeChanges,
            pollIntervalMs: 0,
            stabilityChecks: 1
        )
        await driver.runTurn(userMessage: "hello", isFirstMessage: false) { _ in }
        #expect(bridge.clickedSelectors.contains(".custom-model"))
        #expect(bridge.typed.count == 1)
        #expect(bridge.sendClicks == 1)
    }
}

@Suite("ChatGPT auto-model bypass (audit 2026-09-08)")
struct ChatGPTAutoBypassTests {
    @Test("Missing switcher does not block send for ChatGPT Auto labels")
    func autoLabelSkipsModelMenu() async {
        // The 2026 ChatGPT UI has no model switcher: the dropdown selector
        // matches nothing on the page. A synthetic "ChatGPT Auto…" selection
        // must not fail the turn — there is nothing to inject.
        final class NoSwitcherBridge: BrowserAutomationBridge, @unchecked Sendable {
            var typed = 0
            func navigate(to url: String) async throws {}
            func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws { typed += 1 }
            func click(selector: String) async throws {}
            func clickByText(selector: String, text: String) async throws -> Bool { false }
            func readText(selector: String) async throws -> String { "" }
            func responseFingerprint(selector: String) async throws -> String { "" }
            func exists(selector: String) async throws -> Bool { false }
            func pageText() async throws -> String { "" }
            func currentURL() async throws -> String { "https://chatgpt.com/" }
            func cookies() async throws -> [BrowserCookie] { [] }
            func setCookies(_ cookies: [BrowserCookie]) async throws {}
            func screenshot(selector: String?) async throws -> Data { Data() }
            func wait(ms: Int) async {}
        }
        struct NoopExecutor: WebToolExecutor {
            func execute(_ call: WebToolCall) async -> String { "ok" }
            func execute(_ call: WebToolCall, userApproved: Bool) async -> String { "ok" }
        }
        let bridge = NoSwitcherBridge()
        let driver = WebChatDriver(
            bridge: bridge,
            executor: NoopExecutor(),
            selectors: WebVendorSelectors(
                input: "textarea",
                sendButton: "button.send",
                responseContainer: "div.response",
                stopButton: "button.stop"
            ),
            config: WebProviderConfig(vendor: .chatgpt, selectedModel: "ChatGPT Auto (Instant)"),
            projectRoot: "/tmp",
            accessLevel: .askBeforeChanges,
            pollIntervalMs: 0,
            stabilityChecks: 1
        )
        var events: [WebChatEvent] = []
        // exists() is false everywhere, so sendMessage throws before typing;
        // the assertion is that NO modelInjectionFailed event is emitted for
        // the auto label — the turn fails on the missing input, honestly.
        await driver.runTurn(userMessage: "hello", isFirstMessage: false) { events.append($0) }
        #expect(!events.contains { if case .modelInjectionFailed = $0 { return true }; return false })
    }
}
