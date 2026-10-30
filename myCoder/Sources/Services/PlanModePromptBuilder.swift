import Foundation

/// Системный промпт режима «План».
///
/// Правила сверены с opencode v2.1.4 (plan-агент): режим только для
/// чтения/обсуждения; файлы плана создаются только по явной просьбе; по
/// просьбе реализовать изменения нужно сказать пользователю переключиться
/// на build-режим. Раньше режим «План» использовал ТОТ ЖЕ промпт, что и
/// обычная отправка — исполнитель не знал, что он в plan-режиме.
enum PlanModePromptBuilder {

    /// Напоминание plan-режима. Строки-якоря совпадают с opencode v2.1.4
    /// (проверено strings-анализом бинарника): «You are in Plan mode.…»
    static func systemReminder(planDirectory: String? = nil) -> String {
        var text = """
        You are in Plan mode. Discuss the plan with the user directly in the conversation. Do not create or update plan files unless the user explicitly asks you to; when they do, write them only in:
        \(planDirectory ?? ".opencode/plan")

        You remain in Plan mode until the user switches agents. If the user asks you to implement changes, do not do so. Tell them they need to switch agents.
        """
        return text
    }

    /// Добавляет напоминание только в plan-режиме; build/compose не меняются.
    static func resolve(agentMode: AgentMode, baseSystemPrompt: String) -> String {
        guard agentMode == .plan else { return baseSystemPrompt }
        return baseSystemPrompt + "\n\n" + systemReminder()
    }
}
