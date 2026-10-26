import Testing
import Foundation
@testable import myCoder

@Suite("Slash command execution + session goal (plan Раздел 5 Блок 1/3)")
struct SlashCommandExecutorTests {

    @Test func goalWithArgumentSetsGoal() {
        let exec = SlashCommandExecutor(hasGitRepo: true)
        #expect(exec.execute("/goal improve chat perf") == .setSessionGoal("improve chat perf"))
    }

    @Test func goalWithoutArgumentShowsGoal() {
        let exec = SlashCommandExecutor(hasGitRepo: true)
        #expect(exec.execute("/goal") == .showSessionGoal)
    }

    @Test func planEntersPlanMode() {
        #expect(SlashCommandExecutor(hasGitRepo: true).execute("/plan") == .enterPlanMode)
    }

    @Test func commitOpensComposerWhenGitPresent() {
        #expect(SlashCommandExecutor(hasGitRepo: true).execute("/commit") == .openCommitComposer)
    }

    @Test func gitCommandsFailCleanlyWithoutRepo() {
        let exec = SlashCommandExecutor(hasGitRepo: false)
        #expect(exec.execute("/commit") == .gitRequiredError(command: "commit"))
        #expect(exec.execute("/pr") == .gitRequiredError(command: "pr"))
        #expect(exec.execute("/review") == .gitRequiredError(command: "review"))
    }

    @Test func nonGitCommandsWorkWithoutRepo() {
        let exec = SlashCommandExecutor(hasGitRepo: false)
        if case .injectInstruction = exec.execute("/explain foo") {} else {
            Issue.record("expected injectInstruction")
        }
    }

    @Test func unknownCommandListsAvailable() {
        let exec = SlashCommandExecutor(hasGitRepo: true)
        let action = exec.execute("/nonexistent")
        if case .unknownCommand(let name, let available) = action {
            #expect(name == "nonexistent")
            #expect(available.contains("goal"))
            #expect(available.contains("verify"))
        } else {
            Issue.record("expected unknownCommand, got \(action)")
        }
    }

    @Test func nonCommandTextPassesThrough() {
        #expect(SlashCommandExecutor(hasGitRepo: true).execute("hello there") == .passthrough("hello there"))
    }

    @Test func injectInstructionCommandsProduceInstruction() {
        let exec = SlashCommandExecutor(hasGitRepo: true)
        if case .injectInstruction(let s) = exec.execute("/test") {
            #expect(s.contains("tests"))
        } else { Issue.record("expected injectInstruction") }
        if case .injectInstruction(let s) = exec.execute("/verify") {
            #expect(s.contains("Verify"))
        } else { Issue.record("expected injectInstruction") }
    }

    @Test func compactCommandMapsToCompactionAction() {
        let exec = SlashCommandExecutor(hasGitRepo: false)
        #expect(exec.execute("/compact") == .compactConversation)
        // Compaction must never be sent to the model as raw text.
        if case .injectInstruction = exec.execute("/compact") {
            Issue.record("/compact must not inject an instruction")
        }
    }

    @Test func executingCommandRecordsUsage() {
        SlashCommandRegistry.resetHistory()
        _ = SlashCommandExecutor(hasGitRepo: true).execute("/goal x")
        #expect(SlashCommandRegistry.usageHistory().contains("goal"))
        SlashCommandRegistry.resetHistory()
    }

    // MARK: - Session goal

    @Test func applySetGoalStoresText() {
        let goal = SessionGoalLogic.apply(action: .setSessionGoal("ship v2"), current: nil)
        #expect(goal?.text == "ship v2")
    }

    @Test func applyEmptyGoalClears() {
        let existing = SessionGoal(text: "old")
        #expect(SessionGoalLogic.apply(action: .setSessionGoal(""), current: existing) == nil)
    }

    @Test func applyOtherActionKeepsCurrent() {
        let existing = SessionGoal(text: "keep")
        #expect(SessionGoalLogic.apply(action: .enterPlanMode, current: existing) == existing)
    }

    @Test func badgeLabelTruncatesLongGoal() {
        let short = SessionGoalLogic.badgeLabel(for: SessionGoal(text: "fix bug"))
        #expect(short == "🎯 fix bug")
        let long = SessionGoalLogic.badgeLabel(for: SessionGoal(text: String(repeating: "x", count: 60)))
        #expect(long?.hasSuffix("…") == true)
        #expect(SessionGoalLogic.badgeLabel(for: nil) == nil)
    }

    @Test func sessionGoalCodableRoundTrip() throws {
        let goal = SessionGoal(text: "goal", setAt: Date(timeIntervalSince1970: 1000))
        let data = try JSONEncoder().encode(goal)
        let decoded = try JSONDecoder().decode(SessionGoal.self, from: data)
        #expect(decoded == goal)
    }
}
