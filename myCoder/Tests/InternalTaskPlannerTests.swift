import Foundation
import Testing
@testable import myCoder

@Suite("Internal task planner evidence and questions")
struct InternalTaskPlannerTests {
    @Test func promptIncludesTaskGraphAndAvailableSkills() {
        let context = LocalPlannerContext(
            entities: [.init(kind: .file, path: "FrameStore.swift", name: "FrameStore")],
            memoryTags: ["storage"],
            taskContext: "User: move frames from folders into RAM. Memory: keep export available.",
            graphContext: "SettingsView.chooseFolder → FrameStore.save [heuristic]",
            skillIDs: ["swift-review"]
        )
        let prompt = LocalPlannerPromptBuilder.build(message: "finish migration", context: context)
        #expect(prompt.user.contains("keep export available"))
        #expect(prompt.user.contains("SettingsView.chooseFolder"))
        #expect(prompt.user.contains("swift-review"))
        #expect(prompt.system.contains("questions"))
        #expect(prompt.system.contains("skills"))
        #expect(prompt.system.contains("UI"))
    }

    @Test func plannerQuestionsAndSkillsSurviveValidation() throws {
        let raw = #"{"intent":"refactor","files":["FrameStore.swift"],"questions":["Does the folder picker still serve export (or can it be removed)?"],"skills":["swift-review","invented-skill"]}"#
        let parsed = try LocalQueryPlanParser.parse(raw)
        let context = LocalPlannerContext(
            entities: [.init(kind: .file, path: "FrameStore.swift", name: "FrameStore")],
            memoryTags: [], skillIDs: ["swift-review"]
        )
        let resolved = LocalQueryPlanParser.resolve(parsed, context: context)
        #expect(resolved.plan.questions == ["Does the folder picker still serve export (or can it be removed)?"])
        #expect(resolved.plan.skills == ["swift-review"])
        #expect(resolved.dropped.contains("skill:invented-skill"))
    }

    @Test func questionsAloneAreAUsefulPlan() throws {
        let plan = try LocalQueryPlanParser.parse(#"{"questions":["Which settings become obsolete after moving frames into memory?"]}"#)
        #expect(!plan.isEmpty)
    }

    @Test func questionBoundsRejectOversizedOutput() {
        let raw = "{\"questions\":[\"" + String(repeating: "x", count: 401) + "\"]}"
        #expect(throws: LocalQueryPlanError.valueTooLong(field: "questions")) {
            try LocalQueryPlanParser.parse(raw)
        }
    }

    @Test func promptBoundsBackgroundEvidenceAndCatalog() {
        let context = LocalPlannerContext(
            entities: [], memoryTags: [],
            taskContext: "TASK_START " + String(repeating: "t", count: 20_000) + " TASK_END",
            graphContext: "GRAPH_START " + String(repeating: "g", count: 20_000) + " GRAPH_END",
            skillIDs: (0..<500).map { "skill-\($0)" }
        )
        let prompt = LocalPlannerPromptBuilder.build(message: "request", context: context)
        #expect(prompt.user.contains("TASK_START"))
        #expect(prompt.user.contains("GRAPH_START"))
        #expect(!prompt.user.contains("TASK_END"))
        #expect(!prompt.user.contains("GRAPH_END"))
        #expect(!prompt.user.contains("skill-499"))
        #expect(prompt.user.count < 18_000)
    }

    @Test func legacyPlanAndContextInitializersStillWork() {
        let plan = LocalQueryPlan(intent: .fix, terms: ["frame"], symbols: [], files: [], memoryTags: [])
        let context = LocalPlannerContext(entities: [], memoryTags: [])
        #expect(plan.questions.isEmpty)
        #expect(plan.skills.isEmpty)
        #expect(context.taskContext.isEmpty)
        #expect(context.graphContext.isEmpty)
        #expect(context.skillIDs.isEmpty)
    }
}
