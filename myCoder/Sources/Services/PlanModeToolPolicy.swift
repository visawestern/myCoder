import Foundation

/// Политика тулов в режимах «План» и «Compose».
///
/// Оба режима — только для чтения: запросы на безопасность/одобрения
/// (промпты пользователю) показывать НЕ нужно (директива 2026-10-30,
/// расширена на compose 2026-11-05). Мутирующие тулы (write_file/edit_file/
/// patch/git-коммиты/todo_write/task_* и т.п.) и пишущие шелл-команды
/// отклоняются без вопроса — модели возвращается текст-отказ, как в
/// opencode plan-агенте (права edit/write/patch запрещены). Только
/// читающие команды (включая баш-тулы вроде `ls`/`grep`/`git status`)
/// выполняются как обычно.
///
/// Исключение (директива 2026-11-08): в режиме «План» модель ВЕДЁТ план —
/// создание и обновление шагов плана (task_create/task_update/todo_write)
/// разрешено, потому что они не изменяют состояние проекта, а лишь
/// планировочную структуру. В compose эти тулы остаются запрещёнными.
enum PlanModeToolPolicy {

    enum Decision: Equatable {
        case execute
        case deny(reason: String)
    }

    /// Видимое объяснение отказа для модели.
    static let deniedReason =
        "Plan mode is read-only: this tool call was not executed. Switch to build mode to make changes."

    /// Признак режима только для чтения (plan и compose).
    static func isReadOnlyMode(_ mode: AgentMode) -> Bool {
        mode == .plan || mode == .compose
    }

    static func decision(for call: WebToolCall, mode: AgentMode) -> Decision {
        guard isReadOnlyMode(mode) else { return .execute }

        // Канонизируем алиасы (например "Bash" → run_command) и имя тула.
        let call = WebToolProtocolEmulator.canonicalized(call)
        guard let tool = WebEmulatedTool(rawValue: call.name) else {
            // Неизвестный тул в read-only режиме — fail closed.
            return .deny(reason: deniedReason)
        }

        switch tool {
        // Мутирующие тулы (файлы, гит, сабагенты) — всегда отклоняются без
        // вопроса в обоих read-only режимах.
        case .writeFile, .editFile, .gitBranch, .gitCheckout, .gitCommit,
             .gitPush, .gitPull, .task:
            return .deny(reason: deniedReason)

        // Планировочные тулы: в plan-режиме модель ведёт план (создание/
        // обновление шагов), в compose они запрещены (строгий read-only).
        case .todoWrite, .taskCreate, .taskUpdate:
            if mode == .plan {
                return .execute
            }
            return .deny(reason: deniedReason)

        // Шелл: только читающие команды. Пишущие — отклоняются.
        case .runCommand:
            let args = WebToolProtocolEmulator.normalizedArguments(for: .runCommand, from: call.arguments)
            let command = args["command"] ?? ""
            return WebToolAccessGate.isReadOnlyCommand(command) ? .execute : .deny(reason: deniedReason)

        // Read-only тулы (read_file/list_dir/grep/glob/git_status/git_log/
        // git_diff/todo_read/code_search/read_symbol/web_fetch/browser_fetch/
        // skill/task_list) — выполняются как обычно.
        default:
            return .execute
        }
    }
}
