import Foundation
import Testing
@testable import myCoder

struct PlannerSourceBudgetTests {
    @Test func longHistoryCannotEvictMemoryRulesAndSkills() {
        let text = TurnContextPlanningService.taskEvidence(history: String(repeating: "old history ", count: 2000), ledger: "TASK_STATE", facts: "MEMORY_FACT", rules: "PROJECT_RULE", skills: "SKILL_DESCRIPTION")
        for marker in ["TASK_STATE", "MEMORY_FACT", "PROJECT_RULE", "SKILL_DESCRIPTION"] {
            #expect(text.contains(marker))
        }
        #expect(text.count <= 6000)
    }
}
