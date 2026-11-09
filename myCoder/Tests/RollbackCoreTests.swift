import Testing
import Foundation
@testable import myCoder

/// Ядро полноценного отката диалога: планирование, оценка необратимых
/// действий, границы безопасности, промпт для внутренней модели и
/// исполнение с корзиной. Директива 2026-11-09.
@Suite("Откат — планирование и исполнение")
struct RollbackCoreTests {

    // MARK: - Хелперы

    private func message(_ id: String, at t: Double, role: String = "user", content: String = "текст") -> RollbackMessageRef {
        RollbackMessageRef(id: id, createdAt: t, role: role, content: content)
    }

    private func undo(_ id: String, path: String, at t: Double, snapshot: String? = "snap", canUndo: Bool = true) -> RollbackUndoEntryRef {
        RollbackUndoEntryRef(id: id, path: path, snapshotID: snapshot, actionType: "edit_file", canUndo: canUndo, createdAt: t)
    }

    private func action(messageID: String, tool: String) -> IrreversibleAgentAction {
        IrreversibleAgentAction(messageID: messageID, toolName: tool)
    }

    // MARK: - План: полный откат

    @Test("Полный откат: без блокеров все undo-шаги done, диалог урезается до запроса")
    func fullRollbackPlan() {
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant"),
                        message("q2", at: 3), message("a2", at: 4, role: "assistant")]
        let entries = [undo("u1", path: "src/a.swift", at: 3.5),
                       undo("u2", path: "src/b.swift", at: 3.8)]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "q2",
            messages: messages,
            undoEntries: entries,
            irreversibleActions: [])
        #expect(plan.full)
        #expect(plan.steps.count == 2)
        #expect(plan.steps.allSatisfy { $0.status == .done })
        #expect(plan.visibilityCutMessageID == "q2")
        #expect(plan.stopReason == nil)
    }

    @Test("Полный откат без изменений после запроса — пустой план, full")
    func fullRollbackPlanNoChanges() {
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant")]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "q1",
            messages: messages,
            undoEntries: [],
            irreversibleActions: [])
        #expect(plan.full)
        #expect(plan.steps.isEmpty)
        #expect(plan.visibilityCutMessageID == "q1")
    }

    // MARK: - План: частичный откат (блокер)

    @Test("Необратимое действие после запроса → частьчный откат с границей до блокера")
    func partialRollbackAtIrreversibleAction() {
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant"),
                        message("q2", at: 3), message("a2", at: 4, role: "assistant"),
                        message("q3", at: 5), message("a3", at: 6, role: "assistant")]
        let entries = [undo("u1", path: "src/a.swift", at: 4.5)]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "q2",
            messages: messages,
            undoEntries: entries,
            irreversibleActions: [action(messageID: "q3", tool: "run_command")])
        #expect(!plan.full)
        #expect(plan.stopReason != nil)
        #expect(plan.stopReason?.contains("run_command") == true)
        // Граница — последнее видимое сообщение перед блокером: "a2".
        #expect(plan.visibilityCutMessageID == "a2")
        // Безопасные undo-шаги всё равно выполняются (они не затрагивают блокер).
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].status == .done)
    }

    @Test("Блокер сразу после запроса → граница = сам запрос, откат невозможен")
    func irreversibleImmediatelyAfterTarget() {
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant"),
                        message("q2", at: 3), message("a2", at: 4, role: "assistant")]
        let entries = [undo("u1", path: "src/a.swift", at: 3.5)]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "q2",
            messages: messages,
            undoEntries: entries,
            irreversibleActions: [action(messageID: "a2", tool: "run_command")])
        #expect(!plan.full)
        #expect(plan.visibilityCutMessageID == "q2")
    }

    @Test("Целевой запрос не найден → план неполный с причиной")
    func targetNotFound() {
        let messages = [message("q1", at: 1)]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "missing",
            messages: messages,
            undoEntries: [],
            irreversibleActions: [])
        #expect(!plan.full)
        #expect(plan.stopReason != nil)
    }

    @Test("Использованная undo-запись → шаг blocked с причиной")
    func alreadyUsedEntryBlocked() {
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant")]
        let entries = [undo("u1", path: "src/a.swift", at: 1.5, canUndo: false)]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "q1",
            messages: messages,
            undoEntries: entries,
            irreversibleActions: [])
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].status == .blocked)
        #expect(plan.steps[0].reason != nil)
        // Блокировка шага не делает план «неполным» — файл уже откачен,
        // просто повторять не нужно; граница остаётся целевой.
        #expect(plan.full)
    }

    // MARK: - План: возврат промпта

    @Test("Полный откат последнего запроса возвращает его текст в composer")
    func promptRestoreForLastRequest() {
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant"),
                        message("q2", at: 3, content: "сделай X")]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "q2",
            messages: messages,
            undoEntries: [],
            irreversibleActions: [])
        #expect(plan.promptRestore == "сделай X")
    }

    @Test("Откат к не-последнему запросу не возвращает промпт")
    func noPromptRestoreForMiddleRequest() {
        // q2 — не последний ЗАПРОС: после него есть ещё q3.
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant"),
                        message("q2", at: 3, content: "сделай X"), message("a2", at: 4, role: "assistant"),
                        message("q3", at: 5), message("a3", at: 6, role: "assistant")]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "q2",
            messages: messages,
            undoEntries: [],
            irreversibleActions: [])
        #expect(plan.promptRestore == nil)
    }

    @Test("Последний запрос с ответом модели: промпт всё равно возвращается")
    func promptRestoreForLastRequestWithAssistantAnswer() {
        // Ответ ассистента не делает запрос «не последним»: он будет удалён
        // урезанием диалога, а текст запроса должен вернуться в composer.
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant"),
                        message("q2", at: 3, content: "сделай X"), message("a2", at: 4, role: "assistant")]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "q2",
            messages: messages,
            undoEntries: [],
            irreversibleActions: [])
        #expect(plan.full)
        #expect(plan.promptRestore == "сделай X")
    }

    @Test("Системный чип после запроса не мешает возврату промпта")
    func promptRestoreIgnoresSystemMessages() {
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant"),
                        message("q2", at: 3, content: "сделай X"),
                        message("chip", at: 4, role: "system")]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "q2",
            messages: messages,
            undoEntries: [],
            irreversibleActions: [])
        #expect(plan.promptRestore == "сделай X")
    }

    @Test("Откат к сообщению модели не возвращает промпт")
    func noPromptRestoreForAssistantTarget() {
        let messages = [message("q1", at: 1), message("a1", at: 2, role: "assistant")]
        let plan = RollbackPlanLogic.makePlan(
            targetMessageID: "a1",
            messages: messages,
            undoEntries: [],
            irreversibleActions: [])
        #expect(plan.promptRestore == nil)
    }

    // MARK: - Промпт внутренней модели

    @Test("Промпт показывает диалог и вызовы тулов, вердикт парсится")
    func promptShowsDialogAndParsesVerdict() {
        let messages = [message("q1", at: 1, content: "вопрос"),
                        message("a1", at: 2, role: "assistant", content: "ответ")]
        let prompt = RollbackPromptBuilder.userPrompt(
            targetMessageID: "q1",
            messages: messages,
            irreversibleActions: [IrreversibleAgentAction(messageID: "a1", toolName: "run_command")])
        #expect(prompt.contains("вопрос"))
        #expect(prompt.contains("ответ"))
        #expect(prompt.contains("run_command"))

        let verdict = RollbackPromptBuilder.parseVerdict(
            #"{"canRollback": false, "irreversible": ["run_command"], "stopAtMessageID": "a1"}"#)
        #expect(verdict?.canRollback == false)
        #expect(verdict?.irreversible == ["run_command"])
        #expect(verdict?.stopAtMessageID == "a1")
        #expect(verdict?.valid == true)
    }

    @Test("Битый вердикт → nil (invalid)")
    func brokenVerdictInvalid() {
        let verdict = RollbackPromptBuilder.parseVerdict("не json")
        #expect(verdict == nil)
    }

    @Test("Кодек чипа отката: encode/decode round-trip")
    func chipCodecRoundTrip() {
        let plan = RollbackPlan(targetMessageID: "q1", full: true, steps: [],
                                visibilityCutMessageID: "q1", stopReason: nil, promptRestore: nil)
        let report = RollbackReport(plan: plan, stages: [], diffs: [], error: nil)
        let chip = RollbackChipData(createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                                    full: true, summary: "Откат: 2 файла", report: report)
        guard let encoded = RollbackChipCodec.encode(chip) else {
            Issue.record("encode вернул nil")
            return
        }
        #expect(encoded.hasPrefix(RollbackChipCodec.marker))
        #expect(RollbackChipCodec.decode(from: encoded) == chip)
        #expect(RollbackChipCodec.decode(from: "обычный текст") == nil)
    }
}
