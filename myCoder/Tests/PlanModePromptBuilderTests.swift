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

        let plan = PlanModePromptBuilder.resolve(agentMode: .plan, baseSystemPrompt: base)
        XCTAssertTrue(plan.hasPrefix(base), "базовый промпт должен сохраняться")
        XCTAssertTrue(plan.contains("You are in Plan mode."), "в plan-режиме добавляется напоминание opencode")
    }

    func testResolveAppendsComposeReminderInComposeMode() {
        let base = "BASE PROMPT"
        let compose = PlanModePromptBuilder.resolve(agentMode: .compose, baseSystemPrompt: base)
        XCTAssertTrue(compose.hasPrefix(base), "базовый промпт должен сохраняться")
        XCTAssertTrue(compose.contains("You are in Compose mode."), "в compose-режиме добавляется описание режима")
        XCTAssertFalse(compose.contains("You are in Plan mode."), "compose не должен говорить про plan")
    }

    func testPlanReminderIncludesTodoToolGuidance() {
        let text = PlanModePromptBuilder.systemReminder()
        XCTAssertTrue(
            text.contains("todo") && text.contains("plan"),
            "в plan-режиме должно быть руководство по работе с todo-тулами для обновления плана"
        )
        XCTAssertTrue(
            text.contains("task_list") || text.contains("task_create") || text.contains("task_update"),
            "todo-руководство должно называть конкретные тулы"
        )
    }

    func testComposeReminderDescribesCompositionMode() {
        let text = PlanModePromptBuilder.composeReminder()
        XCTAssertTrue(text.contains("You are in Compose mode."), "должна быть строка открытия compose-режима")
        XCTAssertTrue(text.contains("read-only") || text.contains("do not write"), "compose должен объяснять запрет записи")
        XCTAssertTrue(text.contains("switch to build mode"), "compose должен указывать переключиться на build")
    }
}
