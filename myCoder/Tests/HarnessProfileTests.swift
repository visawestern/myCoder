import Testing
import Foundation
@testable import myCoder

@MainActor
@Suite("Harness profiles C2 (eval harness-tax)")
struct HarnessProfileTests {

    @Test func coreToolsAreFive() {
        let core = Set(WebEmulatedTool.allCases.filter { $0.isCore }.map(\.rawValue))
        #expect(core == ["read_file", "write_file", "edit_file", "list_dir", "run_command"])
    }

    @Test func profileToolSets() {
        #expect(HarnessProfile.minimal.tools.count == 5)
        #expect(HarnessProfile.standard.tools.count == 13)
        #expect(HarnessProfile.full.tools.count == WebEmulatedTool.allCases.count)
        #expect(HarnessProfile.unknown.tools.count == WebEmulatedTool.allCases.count)
        let standard = Set(HarnessProfile.standard.tools.map(\.rawValue))
        #expect(standard.isSuperset(of: [
            "grep", "glob", "git_status", "git_diff", "todo_read", "todo_write",
            "code_search", "read_symbol"
        ]))
        #expect(!standard.contains("git_push"))
    }

    @Test func minimalPreambleIsShorter() {
        let full = WebToolProtocolEmulator.systemPreamble(profile: .full)
        let minimal = WebToolProtocolEmulator.systemPreamble(profile: .minimal)
        #expect(minimal.utf8.count < full.utf8.count)
        #expect(minimal.contains("- read_file args:"))
        #expect(!minimal.contains("- git_push args:"))
        #expect(minimal.contains("available on request"))
        #expect(minimal.contains("git_push"))
        #expect(minimal.contains("```tool"))
    }

    @Test func defaultPreambleIsFull() {
        let def = WebToolProtocolEmulator.systemPreamble()
        let full = WebToolProtocolEmulator.systemPreamble(profile: .full)
        #expect(def == full)
    }

    @Test func budgetTruncatesUserPromptNotProtocol() {
        let longPrompt = String(repeating: "x", count: 5000)
        let out = WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: longPrompt, profile: .minimal, budgetBytes: 3000)
        #expect(out.utf8.count <= 3000)
        #expect(out.contains("```tool"))
        #expect(out.contains("list_dir"))
        #expect(out.contains("[truncated]"))
    }

    @Test func tinyBudgetKeepsProtocolIntact() {
        let out = WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: String(repeating: "y", count: 100),
            profile: .minimal, budgetBytes: 100)
        // Wire format is never cut even when the budget can't fit the base.
        #expect(out.contains("```tool"))
        #expect(out.contains("Tools:"))
    }

    @Test func noBudgetKeepsFullPrompt() {
        let prompt = "custom instructions here"
        let out = WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: prompt, profile: .minimal)
        #expect(out.contains(prompt))
        #expect(!out.contains("[truncated]"))
    }
}

/// Regression (2026-11-03): adding `browser_fetch` to the tool list pushed the
/// first-turn preamble past the vendor paste budget, so the tool contract was
/// split into continuation parts and the model never saw it as one message.
@MainActor
@Suite("Преамбула влезает в бюджет вставки")
struct PreambleBudgetTests {

    @Test("Полная преамбула с префиксом пользователя не больше бюджета чанкера")
    func preambleFitsChunkerBudget() {
        let preamble = WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: "",
            projectRoot: "/Users/x/project",
            isGitRepo: true
        )
        let bytes = preamble.utf8.count
        #expect(bytes <= WebPromptChunker.defaultBudget,
                "преамбула \(bytes) Б превышает бюджет \(WebPromptChunker.defaultBudget) Б")
    }

    @Test("Первый ход с обычным вопросом не режется на части")
    func firstTurnIsNotChunked() {
        let preamble = WebToolProtocolEmulator.systemPreamble(
            userSystemPrompt: "",
            projectRoot: "/Users/x/project",
            isGitRepo: true
        )
        let message = preamble + "\n\n---\n\n" + "task"
        let parts = WebPromptChunker.chunkedMessages(message)
        #expect(parts.count == 1, "первый ход разрезан на \(parts.count) части")
    }
}
