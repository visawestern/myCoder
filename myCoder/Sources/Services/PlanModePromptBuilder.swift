import Foundation

/// Системный промпт режимов «План» и «Compose».
///
/// Правила сверены с opencode v2.1.4 (plan-агент): режимы только для
/// чтения/обсуждения; файлы плана создаются только по явной просьбе; по
/// просьбе реализовать изменения нужно сказать пользователю переключиться
/// на build-режим. Раньше режимы «План»/«Compose» использовали ТОТ ЖЕ
/// промпт, что и обычная отправка — исполнитель не знал, в каком он
/// режиме.
enum PlanModePromptBuilder {

    /// Напоминание plan-режима. Строки-якоря совпадают с opencode v2.1.4
    /// (проверено strings-анализом бинарника): «You are in Plan mode.…»
    ///
    /// Дополнительно содержит руководство по работе с todo-тулами: в
    /// plan-режиме модель должна вести план через todo_read/task_list/
    /// task_create/task_update, а не прятать его в диалоге.
    static func systemReminder(planDirectory: String? = nil) -> String {
        var text = """
        You are in Plan mode. Discuss the plan with the user directly in the conversation. Do not create or update plan files unless the user explicitly asks you to; when they do, write them only in:
        \(planDirectory ?? ".opencode/plan")

        You remain in Plan mode until the user switches agents. If the user asks you to implement changes, do not do so. Tell them they need to switch agents.

        Maintain the draft plan with the todo tools: read the current state with todo_read (or task_list), and record new steps with task_create / task_update so the plan stays in sync as you and the user refine it. Do not edit source files in this mode.
        """
        return text
    }

    /// Напоминание compose-режима. Сочинение текста/контента без изменений
    /// файлов проекта: read-only политика та же, что в plan.
    static func composeReminder() -> String {
        """
        You are in Compose mode. You compose writing content, prose, and documents for the user. This mode is read-only: you do not create or edit project files, run mutating shell commands, or change settings. If the user asks for file edits or implementation, tell them to switch to build mode.
        """
    }

    /// Adds the mode contract. Plan/Compose reminders are appended after the
    /// transport-specific catalog, so the latest read-only rules take priority.
    static func resolve(agentMode: AgentMode, baseSystemPrompt: String) -> String {
        let reminder: String?
        switch agentMode {
        case .plan: reminder = systemReminder()
        case .compose: reminder = composeReminder()
        case .build: reminder = nil
        }
        guard let reminder else { return baseSystemPrompt }
        return baseSystemPrompt + "\n\n" + reminder
    }
}
