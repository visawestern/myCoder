import Testing
import Foundation
@testable import myCoder

/// The user must see the FULL prompt of a goal — the goal itself, its plan,
/// the continuation instruction and the devil's-advocate verification prompt —
/// both in the composer spoiler and in the right sidebar. A prompt longer
/// than ten wrapped lines must scroll instead of pushing the panel away.
@Suite("Полный промпт цели")
struct GoalPromptTests {

    private func goal(plan: [UserGoal.PlanItem] = []) -> UserGoal {
        UserGoal(title: "Переработать отчёт по продажам", plan: plan, state: .active)
    }

    @Test("Промпт содержит цель, план, продолжение и проверку")
    func promptContainsEveryPart() {
        let plan = [
            UserGoal.PlanItem(title: "Собрать требования", status: .done),
            UserGoal.PlanItem(title: "Сгенерировать отчёт", status: .inProgress)
        ]
        let prompt = GoalPromptBuilder.fullPrompt(goal: goal(plan: plan), language: .russian)

        #expect(prompt.contains("Переработать отчёт по продажам"), "цель должна быть в промпте")
        #expect(prompt.contains("Собрать требования"))
        #expect(prompt.contains("Сгенерировать отчёт"))
        #expect(prompt.contains("[done]"), "статус шага должен быть виден")
        #expect(prompt.contains("[in_progress]"))
        #expect(prompt.contains(GoalVerificationPromptBuilder.continuationMessage(language: .russian)),
                "инструкция продолжения должна быть в промпте")
        #expect(prompt.contains(GoalVerificationPromptBuilder.devilAdvocateSystem(language: .russian)),
                "системный промпт адвоката дьявола должен быть в промпте")
    }

    @Test("Промпт детерминирован — два вызова совпадают")
    func promptIsDeterministic() {
        let first = GoalPromptBuilder.fullPrompt(goal: goal(), language: .russian)
        let second = GoalPromptBuilder.fullPrompt(goal: goal(), language: .russian)
        #expect(first == second)
    }

    @Test("Цель без плана: промпт честно говорит, что план пуст")
    func emptyPlanIsStated() {
        let prompt = GoalPromptBuilder.fullPrompt(goal: goal(), language: .russian)
        #expect(prompt.contains("Переработать отчёт по продажам"))
        #expect(prompt.contains("план пуст"), "пустой план должен быть назван прямо")
    }

    @Test("Английская версия промпта тоже собирается")
    func englishPrompt() {
        let prompt = GoalPromptBuilder.fullPrompt(goal: goal(), language: .english)
        #expect(prompt.contains("Goal:"), "английский промпт должен быть на английском")
        #expect(prompt.contains("Переработать отчёт по продажам"))
    }

    @Test("Промпт длиннее десяти строк — прокручиваемый")
    func longPromptScrolls() {
        let plan = (1...12).map {
            UserGoal.PlanItem(title: "Шаг \($0)", status: .todo)
        }
        let presentation = GoalPromptPresentation(
            text: GoalPromptBuilder.fullPrompt(goal: goal(plan: plan), language: .russian))
        #expect(presentation.lineCount > 10, "промпт должен быть длиннее десяти строк")
        #expect(presentation.exceedsVisibleLines == true)
    }

    @Test("Порог в десять строк: короткий текст не прокручивается")
    func shortTextDoesNotScroll() {
        let presentation = GoalPromptPresentation(text: "Цель: X\nПлан:\n- шаг")
        #expect(presentation.lineCount == 3)
        #expect(presentation.exceedsVisibleLines == false)
    }

    @Test("Полный промпт цели длиннее десяти строк — он прокручивается")
    func fullPromptAlwaysScrolls() {
        // The full prompt carries the goal, the plan, the continuation and the
        // devil's-advocate check, so it is taller than the visible window by
        // design — it must scroll instead of pushing the panel away.
        let presentation = GoalPromptPresentation(
            text: GoalPromptBuilder.fullPrompt(goal: goal(), language: .russian))
        #expect(presentation.lineCount > GoalPromptPresentation.visibleLineLimit)
        #expect(presentation.exceedsVisibleLines == true)
    }

    @Test("Видимых строк — ровно десять")
    func visibleLineLimitIsTen() {
        #expect(GoalPromptPresentation.visibleLineLimit == 10)
    }
}
