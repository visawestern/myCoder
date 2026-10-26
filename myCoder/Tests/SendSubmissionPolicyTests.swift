import Testing
import Foundation
@testable import myCoder

/// Round 30 — live finding: FallbackRouter declared browserAutomation sends
/// "successful" right after one click(), without verifying that the vendor page
/// actually submitted. On a freshly-hydrated qwen.ai page the click lands before
/// React attaches the submit handler → nothing is sent, yet downstream flow
/// trusted the fake success (and the remote-chat gate later blocked honestly).
@Suite("Round 30 — send submission verification logic")
struct SendSubmissionPolicyTests {

    @Test("url gains a chat id → submitted")
    func urlGainMeansSubmitted() {
        #expect(SendSubmissionPolicy.submissionDetected(
            beforeURL: "https://chat.qwen.ai/",
            afterURL: "https://chat.qwen.ai/c/06ee9c0b-916e-4044-9e9f-424ca91f5646"))
        #expect(SendSubmissionPolicy.submissionDetected(
            beforeURL: "https://www.kimi.com/",
            afterURL: "https://www.kimi.com/chat/cv8xk9abcd"))
    }

    @Test("unchanged url is never treated as submitted")
    func unchangedURLNotSubmitted() {
        #expect(!SendSubmissionPolicy.submissionDetected(
            beforeURL: "https://chat.qwen.ai/",
            afterURL: "https://chat.qwen.ai/"))
    }

    @Test("changed url without a chat id is not submission proof")
    func changedURLWithoutChatIDNotSubmitted() {
        #expect(!SendSubmissionPolicy.submissionDetected(
            beforeURL: "https://chat.qwen.ai/",
            afterURL: "https://chat.qwen.ai/?login=1"))
    }

    @Test("chat-id parser handles query, fragment and short junk segments")
    func urlHasChatIDParsing() {
        #expect(SendSubmissionPolicy.urlHasChatID("https://x.io/chat/abc12345-def"))
        #expect(SendSubmissionPolicy.urlHasChatID("https://x.io/c/abc12345?tab=2#top"))
        #expect(!SendSubmissionPolicy.urlHasChatID("https://x.io/chat/"))
        #expect(!SendSubmissionPolicy.urlHasChatID("https://x.io/c/short"))   // <8 chars junk
        #expect(!SendSubmissionPolicy.urlHasChatID("https://x.io/other/abc12345-def"))
        #expect(!SendSubmissionPolicy.urlHasChatID(""))
    }

    @Test("retry budget is small and bounded")
    func retryBudgetBounded() {
        #expect(SendSubmissionPolicy.maxClickAttempts >= 2)
        #expect(SendSubmissionPolicy.maxClickAttempts <= 5)
        #expect(SendSubmissionPolicy.verifyDelayMs >= 800)
        #expect(SendSubmissionPolicy.verifyDelayMs <= 3000)
        #expect(SendSubmissionPolicy.maxMatchRetries >= 2)
        #expect(SendSubmissionPolicy.maxMatchRetries <= 5)
        #expect(SendSubmissionPolicy.matchRetryDelayMs >= 400)
        #expect(SendSubmissionPolicy.matchRetryDelayMs <= 2000)
    }

    @Test("qwen effort candidates cover the live English menu and legacy labels")
    @MainActor
    func qwenEffortLabelsAdaptedToLiveDOM() throws {
        // Round 30b: the live qwen.ai menu renders "Auto"/"Think"/"Fast";
        // the old hardcoded Chinese-only labels could never match it.
        let driver = try makeDriver(vendor: .qwen)
        #expect(driver.effortCandidates(for: .medium)?.contains("Auto") == true,
                "medium must map to the live 'Auto' item")
        #expect(driver.effortCandidates(for: .high)?.contains("Think") == true,
                "high must map to the live 'Think' item")
        #expect(driver.effortCandidates(for: .low)?.contains("Fast") == true,
                "low must map to the live 'Fast' item")
        #expect(driver.effortCandidates(for: .high)?.contains("深度思考") == true,
                "legacy Chinese label retained as fallback")
    }
}

extension SendSubmissionPolicyTests {
    @MainActor
    private func makeDriver(vendor: WebChatVendor) throws -> WebChatDriver {
        var config = WebProviderConfig(vendor: vendor, toolCallDelayMs: 0, acknowledgedToS: true)
        config.selectedModel = ""
        return WebChatDriver(
            bridge: ThrowingBridge(),
            executor: ProjectWebToolExecutor(projectRoot: "/tmp"),
            selectors: WebVendorSelectors(input: "textarea", sendButton: "button",
                                          responseContainer: "div", stopButton: "button"),
            config: config, projectRoot: "/tmp", accessLevel: .fullAccess)
    }

    private final class ThrowingBridge: BrowserAutomationBridge {
        struct Err: Error {}
        func navigate(to url: String) async throws { throw Err() }
        func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool) async throws { throw Err() }
        func click(selector: String) async throws { throw Err() }
        @discardableResult func clickByText(selector: String, text: String) async throws -> Bool { false }
        func readText(selector: String) async throws -> String { "" }
        func responseFingerprint(selector: String) async throws -> String { "" }
        func exists(selector: String) async throws -> Bool { false }
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
