import XCTest
@testable import myCoder

/// Режим «План» должен давать модели ТОТ ЖЕ набор правил, что opencode
/// v2.1.4 в plan-режиме: обсуждение плана, запрет создания/изменения
/// файлов (кроме явной просьбы), запрет реализации изменений и ответ
/// «переключись на build». Строки сверены с бинарником opencode
/// (strings + grep: "You are in Plan mode…").
final class PlanModePromptBuilderTests: XCTestCase {

    func testPlanReminderMatchesOpenCodeSemantics() {
        let text = PlanModePromptBuilder.systemReminder()
        XCTAssertTrue(text.contains("You are in Plan mode."), "должна быть строка открытия plan-режима opencode")
        XCTAssertTrue(
            text.contains("Do not create or update plan files unless the user explicitly asks you to"),
            "запрет создания файлов плана должен совпадать с opencode"
        )
        XCTAssertTrue(
            text.contains("If the user asks you to implement changes, do not do so."),
            "запрет реализации изменений должен совпадать с opencode"
        )
        XCTAssertTrue(
            text.contains("Tell them they need to switch agents."),
            "указание переключиться на build должно совпадать с opencode"
        )
        XCTAssertTrue(
            text.contains("You remain in Plan mode until the user switches agents."),
            "правило «остаёмся в Plan, пока не переключат» должно присутствовать"
        )
    }

    func testResolveAppendsPlanReminderOnlyInPlanMode() {
        let base = "BASE PROMPT"
        XCTAssertEqual(PlanModePromptBuilder.resolve(agentMode: .build, baseSystemPrompt: base), base)
        XCTAssertEqual(PlanModePromptBuilder.resolve(agentMode: .compose, baseSystemPrompt: base), base)

        let plan = PlanModePromptBuilder.resolve(agentMode: .plan, baseSystemPrompt: base)
        XCTAssertTrue(plan.hasPrefix(base), "базовый промпт должен сохраняться")
        XCTAssertTrue(plan.contains("You are in Plan mode."), "в plan-режиме добавляется напоминание opencode")
    }
}
