import Testing
import Foundation
@testable import myCoder

/// Audit 2026-09-06: Claude Web vendor — the fourth first-class web provider
/// (used primarily for textual specs and atomic UI decomposition). Verifies
/// vendor plumbing (enum, catalog entry, selectors, label parsing, effort
/// semantics) through the same contracts the other three vendors follow.
@Suite("Claude Web vendor (audit 2026-09-06)")
struct ClaudeWebVendorTests {

    @Test func vendorEnumCarriesIdentityAndURLs() {
        #expect(WebChatVendor(rawValue: "claude") != nil)
        #expect(WebChatVendor.claude.displayName == "Claude")
        #expect(WebChatVendor.claude.defaultChatURL == "https://claude.ai/new")
        // CaseIterable includes claude without breaking existing decoding.
        #expect(WebChatVendor.allCases.map(\.rawValue).contains("claude"))
    }

    @Test func catalogEntryProvidesSelectorsAndLoginURL() throws {
        let catalog = try WebProviderCatalog.loadBundled()
        let entry = try #require(catalog.selectors(for: "claude"))
        #expect((entry.input ?? "").isEmpty == false)
        #expect((entry.sendButton ?? "").isEmpty == false)
        #expect((entry.responseContainer ?? "").isEmpty == false)
        #expect(entry.modelDropdown.isEmpty == false)
        #expect(catalog.loginURL(for: "claude") == "https://claude.ai/login")
        #expect(catalog.loginURL(for: "kimi") == "https://www.kimi.ai/")
        #expect(catalog.loginURL(for: "qwen") == "https://chat.qwen.ai/auth")
        #expect(catalog.loginURL(for: "chatgpt") == "https://chatgpt.com/auth/login")
    }

    @Test func configDefaultURLFollowsVendor() {
        let config = WebProviderConfig(vendor: .claude)
        #expect(config.chatURL == "https://claude.ai/new")
        #expect(config.displayName == "Claude")
        #expect(config.isReady)
    }

    @Test func modelLabelParserAcceptsClaudeFamiliesOnly() {
        let vendor = WebChatVendor.claude
        #expect(WebModelListParser.isValidModelLabel("Claude Opus 4.5", vendor: vendor))
        #expect(WebModelListParser.isValidModelLabel("Sonnet 4.5", vendor: vendor))
        #expect(WebModelListParser.isValidModelLabel("Claude Haiku 4.5", vendor: vendor))
        // Noise and effort labels must be rejected before persistence.
        #expect(!WebModelListParser.isValidModelLabel("Deep thinking, extended reasoning", vendor: vendor))
        #expect(!WebModelListParser.isValidModelLabel("", vendor: vendor))
        #expect(!WebModelListParser.isValidModelLabel("Settings and preferences for the account", vendor: vendor))
    }

    @MainActor
    @Test func claudeEffortMapsToLiveMenuTiers() {
        // Live 2026 Claude menu exposes "Effort" (Max tier verified on the
        // real page); high must map to the live labels.
        let candidates = SendRoutingForClaudeHelper.effortCandidates(.claude)
        #expect(candidates?.contains("Max") == true)
        #expect(candidates?.contains("High") == true)
    }

    @Test func addAccountAcceptsClaudeVendorAfterExistingConfig() {
        // The clone path requires an existing config; simulate one.
        let defaults = UserDefaults(suiteName: "claude-vendor-test")!
        defaults.removePersistentDomain(forName: "claude-vendor-test")
        WebProviderStore.save([WebProviderConfig(vendor: .claude)], defaults: defaults)
        let loaded = WebProviderStore.load(defaults: defaults)
        #expect(loaded.first?.vendor == .claude)
        defaults.removePersistentDomain(forName: "claude-vendor-test")
    }
}

/// Test-only bridge to the driver's private effort mapping.
enum SendRoutingForClaudeHelper {
    @MainActor
    static func effortCandidates(_ vendor: WebChatVendor) -> [String]? {
        var config = WebProviderConfig(vendor: vendor, toolCallDelayMs: 0)
        config.selectedModel = ""
        let driver = WebChatDriver(
            bridge: ClaudeStubBridge(),
            executor: ProjectWebToolExecutor(projectRoot: "/tmp"),
            selectors: WebVendorSelectors(input: "i", sendButton: "s", responseContainer: "r", stopButton: "b"),
            config: config,
            projectRoot: "/tmp",
            accessLevel: .fullAccess
        )
        return driver.effortCandidates(for: .high)
    }

    private final class ClaudeStubBridge: BrowserAutomationBridge {
        struct Err: Error {}
        func navigate(to url: String) async throws { throw Err() }
        func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws { throw Err() }
        func click(selector: String) async throws { throw Err() }
        @discardableResult func clickByText(selector: String, text: String) async throws -> Bool { false }
        @discardableResult func clickVisibleTextExact(selector: String, text: String) async throws -> Bool { false }
        func readText(selector: String) async throws -> String { "" }
        func responseFingerprint(selector: String) async throws -> String { "" }
        func exists(selector: String) async throws -> Bool { false }
        func waitForSelector(selector: String, timeout: Int) async throws {}
        func readModelItems(modelItemSelector: String) async throws -> [String] { [] }
        func readModelCandidates(modelItemSelector: String) async throws -> [WebModelDOMItem] { [] }
        func readVisibleModelCandidates() async throws -> [WebModelDOMItem] { [] }
        func evaluateJS(_ script: String) async throws -> Any? { "" }
        func pageText() async throws -> String { "" }
        func currentURL() async throws -> String { "" }
        func cookies() async throws -> [BrowserCookie] { [] }
        func setCookies(_ cookies: [BrowserCookie]) async throws {}
        func setLocalStorage(_ values: [String: String]) async throws {}
        func screenshot(selector: String?) async throws -> Data { Data() }
        func stopGeneration() async throws {}
        func wait(ms: Int) async {}
    }
}
