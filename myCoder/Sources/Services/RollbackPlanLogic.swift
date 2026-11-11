import Foundation

/// Детерминированное планирование отката диалога к целевому запросу.
/// Чистая функция: не трогает ни файлы, ни хранилища — только решает,
/// что и до какого момента можно безопасно откатить.
///
/// Правила (директива 2026-11-09):
/// - Откатываем всё, что произошло ПОСЛЕ целевого запроса.
/// - Файловые изменения откатываются из снапшотов undo-стека.
/// - Необратимые действия (run_command и т.п.) образуют барьер: если такой
///   барьер есть, откат становится частичным, видимая часть диалога
///   урезается до сообщения перед барьером, а причина честно сообщается.
/// - Если целевой запрос — последний в чате и откат полный, его текст
///   возвращается в окно ввода промпта, а сам он исчезает из чата.
enum RollbackPlanLogic {

    static func makePlan(
        targetMessageID: String,
        messages: [RollbackMessageRef],
        undoEntries: [RollbackUndoEntryRef],
        irreversibleActions: [IrreversibleAgentAction]
    ) -> RollbackPlan {
        guard let targetIndex = messages.firstIndex(where: { $0.id == targetMessageID }) else {
            return RollbackPlan(
                targetMessageID: targetMessageID,
                full: false,
                steps: [],
                visibilityCutMessageID: nil,
                stopReason: "Целевой запрос не найден в диалоге.",
                promptRestore: nil
            )
        }
        let target = messages[targetIndex]

        // 1. Шаги отката файлов: undo-записи после целевого запроса.
        //
        // Основная связь — номер сообщения модели, во время которого сделана
        // правка: он не зависит от точности часов и однозначно относит правку
        // к ходу диалога. Старые записи без номера сравниваются по времени;
        // оно хранится целыми секундами, поэтому запись в секунду запроса
        // считается «после» (правка физически не могла появиться раньше
        // только что отправленного запроса).
        let targetSecond = floor(target.createdAt)
        let steps = undoEntries
            .filter { entry in
                if let messageID = entry.messageID {
                    guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
                        // Сообщение уже удалено/сжато — честный запасной путь.
                        return entry.createdAt >= targetSecond
                    }
                    return index > targetIndex
                }
                return entry.createdAt >= targetSecond
            }
            .map { entry -> RollbackStep in
                if entry.canUndo, entry.snapshotID != nil {
                    return RollbackStep(entryID: entry.id, snapshotID: entry.snapshotID,
                                        path: entry.path, actionType: entry.actionType,
                                        status: .done, reason: nil)
                }
                let reason = entry.canUndo
                    ? "Снапшот файла отсутствует — восстановление невозможно."
                    : "Это изменение уже было откачено ранее."
                return RollbackStep(entryID: entry.id, snapshotID: entry.snapshotID,
                                    path: entry.path, actionType: entry.actionType,
                                    status: .blocked, reason: reason)
            }

        // 2. Необратимые действия после целевого запроса, по порядку.
        let actionsAfter = irreversibleActions.filter { action in
            guard let idx = messages.firstIndex(where: { $0.id == action.messageID }) else {
                return false
            }
            return idx > targetIndex
        }
        let orderedActions = actionsAfter.sorted { lhs, rhs in
            let a = messages.firstIndex(where: { $0.id == lhs.messageID }) ?? Int.max
            let b = messages.firstIndex(where: { $0.id == rhs.messageID }) ?? Int.max
            return a < b
        }

        // 3. Полный откат: барьеров нет.
        if orderedActions.isEmpty {
            // «Последний запрос» — последнее USER-сообщение, а не последняя
            // строка фида. Ответ модели и системный чип после запроса будут
            // удалены урезанием диалога, поэтому они не должны мешать вернуть
            // текст запроса в поле ввода (иначе возврат промпта недостижим
            // в обычном чате, где на каждый запрос есть ответ).
            let later = messages.suffix(from: targetIndex + 1)
            let isLastRequest = target.role == "user" && !later.contains { $0.role == "user" }
            return RollbackPlan(
                targetMessageID: targetMessageID,
                full: true,
                steps: steps,
                visibilityCutMessageID: targetMessageID,
                stopReason: nil,
                promptRestore: isLastRequest ? target.content : nil
            )
        }

        // 4. Частичный откат: граница — сообщение перед самым ранним барьером,
        //    безопасные undo-шаги всё равно выполняются.
        let earliest = orderedActions[0]
        let barrierIndex = messages.firstIndex(where: { $0.id == earliest.messageID }) ?? targetIndex
        let cutIndex = max(targetIndex, barrierIndex - 1)
        let reasons = orderedActions
            .map { "\($0.toolName) (после «\($0.messageID)»)" }
            .joined(separator: "; ")
        return RollbackPlan(
            targetMessageID: targetMessageID,
            full: false,
            steps: steps,
            visibilityCutMessageID: messages[cutIndex].id,
            stopReason: "Дальше откатить нельзя: необратимые действия — \(reasons).",
            promptRestore: nil
        )
    }
}
