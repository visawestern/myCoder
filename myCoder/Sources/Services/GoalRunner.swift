import Foundation

/// Автономный запуск цели (директива 2026-11-09): «Старт» не просто меняет
/// статус — приложение отправляет полный промпт цели в чат как юзер (тот
/// же send-путь с контекстом), а после каждого ответа проверяет прогресс и
/// продолжает цикл, пока цель не выполнена.
enum GoalRunner {

    /// Сообщение, которое уходит в чат от «юзера» при старте цели — ровно
    /// тот полный промпт, который показан в GoalPromptView.
    static func launchMessage(goal: UserGoal, language: AppLanguage) -> String {
        GoalPromptBuilder.fullPrompt(goal: goal, language: language)
    }

    /// Обновление плана по вердикту адвоката дьявола:
    /// - complete → все шаги done;
    /// - иначе: шаги, которых нет в `notDone`, считаются подтверждённо
    ///   выполненными (done), шаги из `notDone` — текущей работой
    ///   (in_progress), а blocked остаётся blocked.
    static func updatedPlan(_ plan: [UserGoal.PlanItem], verdict: GoalVerdict) -> [UserGoal.PlanItem] {
        if verdict.complete {
            return plan.map { item in
                var copy = item
                copy.status = .done
                copy.note = nil
                return copy
            }
        }
        let notDone = Set(verdict.notDone)
        return plan.map { item in
            var copy = item
            if notDone.contains(copy.title) {
                if copy.status == .todo {
                    copy.status = .inProgress
                }
            } else if copy.status == .todo || copy.status == .inProgress {
                // Blocked is NOT "done": a model that omits a blocked step
                // from notDone must not make the step disappear as completed.
                copy.status = .done
            }
            return copy
        }
    }

    /// Стоит ли продолжать авто-цикл после вердикта.
    static func shouldContinue(after verdict: GoalVerdict) -> Bool {
        !verdict.complete
    }
}

/// Отправка «как юзер»: пишет сообщение в текущий чат через тот же путь,
/// что и обычная отправка (`apiSendRequested`), чтобы собрался полный
/// контекст и модель получила итоговый пакет.
enum GoalLauncher {

    /// Помечает цель активной и просит отправить её стартовый промпт через
    /// обычный send-путь (обработчик `apiSendRequested` в ChatPanelView).
    /// Возвращает `false`, если цель не найдена или уже выполнена.
    @discardableResult
    static func launch(goalID: UUID,
                       homeDirectory: URL,
                       language: AppLanguage,
                       fallbackChatID: String?) -> Bool {
        guard let goal = GoalStore.load(homeDirectory: homeDirectory).first(where: { $0.id == goalID }),
              goal.state != .done else {
            return false
        }
        // A project-scoped or legacy goal becomes bound to the chat it is
        // launched into. Without this, a chatID-less goal would remain
        // project-wide and keep appearing in every chat of the project
        // (user directive 2026-11-13: a goal never jumps between chats).
        // Bind FIRST, then set the state: the upsert carries the old goal
        // value and would otherwise overwrite the freshly-active state.
        let chatID = normalized(goal.chatID) ?? normalized(fallbackChatID)
        if normalized(goal.chatID) == nil, let chatID {
            var bound = goal
            bound.chatID = chatID
            bound.updatedAt = Date()
            _ = try? GoalStore.upsert(bound, homeDirectory: homeDirectory)
            GoalService.notifyChanged()
        }
        _ = try? GoalStore.setState(id: goal.id, state: .active, homeDirectory: homeDirectory)
        let message = GoalRunner.launchMessage(goal: goal, language: language)
        var userInfo: [AnyHashable: Any] = ["message": message]
        if let chatID {
            userInfo["chatId"] = chatID
        }
        NotificationCenter.default.post(
            name: Notification.Name("apiSendRequested"),
            object: nil,
            userInfo: userInfo
        )
        return true
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
