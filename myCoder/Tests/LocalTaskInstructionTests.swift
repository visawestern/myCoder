import Foundation
import Testing
@testable import myCoder

@MainActor
@Suite("Task-specific procedure instructions from internal planner")
struct LocalTaskInstructionTests {
    @Test func selectedProcedureSurvivesParsingAndResolution() throws {
        let raw = #"{"intent":"refactor","instructions":["First add a failing storage contract test, then migrate the producer and its consumers.","Check whether folder selection still serves export before removing settings (including persisted paths)."],"skills":["storage-review","invented"]}"#
        let parsed = try LocalQueryPlanParser.parse(raw)
        let resolved = LocalQueryPlanParser.resolve(parsed, context: .init(entities: [], memoryTags: [], skillIDs: ["storage-review"]))
        #expect(resolved.plan.instructions == [
            "First add a failing storage contract test, then migrate the producer and its consumers.",
            "Check whether folder selection still serves export before removing settings (including persisted paths)."
        ])
        #expect(resolved.plan.skills == ["storage-review"])
        #expect(resolved.dropped == ["skill:invented"])
        #expect(!resolved.plan.isEmpty)
    }

    @Test func legacyPlansDefaultToNoAdditionalInstructions() throws {
        let direct = LocalQueryPlan(intent: .fix, terms: [], symbols: [], files: [], memoryTags: [])
        let parsed = try LocalQueryPlanParser.parse(#"{"terms":["cache"]}"#)
        #expect(direct.instructions.isEmpty)
        #expect(parsed.instructions.isEmpty)
    }

    @Test func duplicateAndBlankInstructionsDoNotInflatePlan() throws {
        let parsed = try LocalQueryPlanParser.parse(#"{"instructions":["  Inspect consumers first.  ","Inspect consumers first.",""]}"#)
        #expect(parsed.instructions == ["Inspect consumers first."])
    }

    @Test func instructionCountAndLengthAreBounded() throws {
        let tooMany = try JSONSerialization.data(withJSONObject: ["instructions": (0..<9).map { "Step \($0)" }])
        #expect(throws: LocalQueryPlanError.tooManyItems(field: "instructions")) {
            try LocalQueryPlanParser.parse(String(decoding: tooMany, as: UTF8.self))
        }
        let tooLong = try JSONSerialization.data(withJSONObject: ["instructions": [String(repeating: "x", count: 401)]])
        #expect(throws: LocalQueryPlanError.valueTooLong(field: "instructions")) {
            try LocalQueryPlanParser.parse(String(decoding: tooLong, as: UTF8.self))
        }
    }

    @Test func executableBlocksAreRejected() {
        #expect(throws: LocalQueryPlanError.codeDetected(field: "instructions")) {
            try LocalQueryPlanParser.parse(#"{"instructions":["```tool write_file```"]}"#)
        }
        #expect(throws: LocalQueryPlanError.wrongType(field: "instructions")) {
            try LocalQueryPlanParser.parse(#"{"instructions":[42]}"#)
        }
    }

    @Test func internalPromptSelectsProcedureByTaskAndPreservesPriority() {
        let prompt = LocalPlannerPromptBuilder.build(message: "move frames into memory", context: .init(entities: [], memoryTags: []))
        #expect(prompt.system.contains("\"instructions\""))
        #expect(prompt.system.contains("HOW to perform"))
        #expect(prompt.system.contains("fix, refactor, add, test, or explain"))
        #expect(prompt.system.contains("migration"))
        #expect(prompt.system.contains("user request and project rules"))
        #expect(prompt.system.contains("Never override"))
    }
}
