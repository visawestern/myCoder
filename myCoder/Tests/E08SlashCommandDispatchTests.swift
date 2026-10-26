import Testing
import Foundation
@testable import myCoder

/// E08 (FEATURE_TEST_REPORT): /plan, /commit, /pr, /review, /context were
/// NO-OPs — ChatPanelView fell through and sent the raw command text to the
/// model (Раздел 5 п.12-16). Each must now produce a REAL side effect:
///   п.12 /plan → switch to plan agent mode
///   п.13 /review → open the review dialog for the pending diff
///   п.15 /commit → open the commit composer
///   п.16 /pr → create a PR (or publish wizard when no remote exists)
///   п.23 /context → show workspace/branch/model/provider context in chat
///   п.14 /test → inject instruction with the DETECTED test runner
@Suite("E08 — slash commands dispatch real side effects")
struct E08SlashCommandDispatchTests {

    private func context(
        hasGitRepo: Bool = true,
        hasRemote: Bool = false,
        branch: String? = "main",
        modelID: String = "gpt-4o",
        providerID: String = "openai",
        agentMode: String = "build",
        workspacePath: String? = "/tmp/proj",
        testRunner: String? = nil,
        changedFileCount: Int = 3
    ) -> SlashDispatchContext {
        SlashDispatchContext(
            hasGitRepo: hasGitRepo,
            hasRemote: hasRemote,
            branch: branch,
            modelID: modelID,
            providerID: providerID,
            agentMode: agentMode,
            workspacePath: workspacePath,
            testRunner: testRunner,
            changedFileCount: changedFileCount
        )
    }

    // MARK: /plan (п.12)

    @Test("/plan switches to plan agent mode, never sends text")
    func planSwitchesAgentMode() {
        let effects = SlashCommandDispatcher.effects(for: .enterPlanMode, context: context())
        #expect(effects.contains(.setAgentMode("plan")))
        #expect(!effects.contains(where: { if case .injectInstruction = $0 { return true }; return false }))
        #expect(effects.contains(.clearInput))
    }

    // MARK: /commit (п.15)

    @Test("/commit opens the commit composer when git repo exists")
    func commitOpensComposer() {
        let effects = SlashCommandDispatcher.effects(for: .openCommitComposer, context: context())
        #expect(effects.contains(.openGitAction(.openCommitComposer)))
        #expect(!effects.contains(where: { if case .injectInstruction = $0 { return true }; return false }))
    }

    // MARK: /pr (п.16)

    @Test("/pr with a remote opens the pull request dialog")
    func prWithRemoteOpensPRDialog() {
        let effects = SlashCommandDispatcher.effects(for: .createPullRequest, context: context(hasRemote: true))
        #expect(effects.contains(.openGitAction(.createPullRequest)))
    }

    @Test("/pr without a remote opens the publish wizard instead")
    func prWithoutRemoteOpensPublishWizard() {
        let effects = SlashCommandDispatcher.effects(for: .createPullRequest, context: context(hasRemote: false))
        #expect(effects.contains(.openGitAction(.openPublishWizard)))
    }

    @Test("/pr never sends raw command text")
    func prNeverSendsText() {
        let effects = SlashCommandDispatcher.effects(for: .createPullRequest, context: context(hasRemote: true))
        #expect(!effects.contains(where: { if case .injectInstruction = $0 { return true }; return false }))
    }

    // MARK: /review (п.13)

    @Test("/review opens the review dialog")
    func reviewOpensDialog() {
        let effects = SlashCommandDispatcher.effects(for: .requestReview, context: context())
        #expect(effects.contains(.openGitAction(.openReviewDialog)))
    }

    // MARK: /context (п.23)

    @Test("/context shows branch model and workspace in chat")
    func contextShowsDetails() {
        let effects = SlashCommandDispatcher.effects(for: .showContext, context: context(hasRemote: true, changedFileCount: 7))
        guard let message = effects.compactMap({ effect -> String? in
            if case .appendAssistantMessage(let text) = effect { return text }
            return nil
        }).first else {
            Issue.record("expected an assistant message"); return
        }
        #expect(message.contains("main"))
        #expect(message.contains("gpt-4o"))
        #expect(message.contains("/tmp/proj"))
        #expect(message.contains("7"))
        #expect(!effects.contains(where: { if case .injectInstruction = $0 { return true }; return false }))
    }

    // MARK: /test runner detection (п.14/36)

    @Test("test runner detected from Package.swift")
    func swiftRunnerDetected() {
        #expect(TestRunnerDetector.detect(in: "/p") { $0.hasSuffix("Package.swift") } == "swift test")
    }

    @Test("test runner detected from package.json")
    func npmRunnerDetected() {
        #expect(TestRunnerDetector.detect(in: "/p") { $0.hasSuffix("package.json") } == "npm test")
    }

    @Test("pytest detected from pytest.ini")
    func pytestRunnerDetected() {
        #expect(TestRunnerDetector.detect(in: "/p") { $0.hasSuffix("pytest.ini") } == "pytest")
    }

    @Test("no runner files → nil")
    func noRunnerDetected() {
        #expect(TestRunnerDetector.detect(in: "/p") { _ in false } == nil)
    }

    @Test("/test names the detected runner")
    func testNamesDetectedRunner() {
        let instruction = SlashCommandExecutor(hasGitRepo: true).execute("/test").rawInstruction
        let enriched = SlashCommandDispatcher.enrichTestInstruction(instruction, runner: "swift test")
        #expect(enriched.contains("swift test"))
        #expect(!enriched.contains("Run the project's tests using `nil`"))
    }

    @Test("/test without a detected runner keeps the generic instruction")
    func testWithoutRunnerKeepsGeneric() {
        let instruction = SlashCommandExecutor(hasGitRepo: true).execute("/test").rawInstruction
        #expect(SlashCommandDispatcher.enrichTestInstruction(instruction, runner: nil) == instruction)
    }

    @Test("/test instruction flows through dispatch with runner")
    func testInstructionThroughDispatch() {
        let effects = SlashCommandDispatcher.effects(
            for: .injectInstruction("Run the project's tests and show the result. /test"),
            context: context(testRunner: "pytest")
        )
        let text = effects.compactMap { effect -> String? in
            if case .injectInstruction(let t) = effect { return t }
            return nil
        }.first
        #expect(text?.contains("pytest") == true)
    }
}

extension SlashCommandAction {
    /// Test helper: the raw instruction string for `.injectInstruction` cases.
    var rawInstruction: String {
        if case .injectInstruction(let instruction) = self { return instruction }
        return ""
    }
}
