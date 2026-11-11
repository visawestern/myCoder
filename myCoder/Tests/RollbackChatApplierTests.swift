import Testing
import Foundation
@testable import myCoder

/// Применение результата отката к чату: урезание диалога с архивацией
/// удаляемого в корзину, возврат промпта в поле ввода, добавление чипа.
@MainActor
@Suite("Откат — применение к чату")
struct RollbackChatApplierTests {

    private func message(_ id: String, role: MessageRole = .user) -> Message {
        Message(id: id, role: role, content: "текст \(id)")
    }

    private func chip(plan: RollbackPlan) -> RollbackChipData {
        let report = RollbackReport(plan: plan, stages: [], diffs: [], error: nil)
        return RollbackChipData(createdAt: Date(), full: plan.full, summary: "сводка", report: report)
    }

    private func plan(full: Bool = true, target: String = "q2",
                      cut: String? = "q2", prompt: String? = nil) -> RollbackPlan {
        RollbackPlan(targetMessageID: target, full: full, steps: [],
                     visibilityCutMessageID: cut, stopReason: nil, promptRestore: prompt)
    }

    @Test("Частичный откат: удаляются сообщения после границы, чип добавляется")
    func trimsAfterCutAndAppendsChip() throws {
        let messages = [message("q1"), message("a1", role: .assistant),
                        message("q2"), message("a2", role: .assistant),
                        message("q3"), message("a3", role: .assistant)]
        var removedIDs: [String] = []
        var appended: [Message] = []
        let plan = plan(full: false, cut: "q2")
        let deps = RollbackChatApplier.Dependencies(
            messages: messages, sessionID: "s1",
            homeDirectory: FileManager.default.temporaryDirectory,
            removeMessage: { removedIDs.append($0) },
            appendMessage: { appended.append($0) },
            restorePrompt: { _ in }
        )
        try RollbackChatApplier.apply(chip: chip(plan: plan), dependencies: deps)
        // После границы q2 идут a2, q3, a3 — все удалены в обратном порядке.
        #expect(Set(removedIDs) == Set(["a2", "q3", "a3"]))
        #expect(appended.count == 1)
        #expect(appended[0].role == .system)
        #expect(appended[0].content.hasPrefix(RollbackChipCodec.marker))
    }

    @Test("Полный откат последнего запроса: запрос удалён, промпт возвращён")
    func restoresPromptAndRemovesLastRequest() throws {
        let messages = [message("q1"), message("a1", role: .assistant), message("q2")]
        var removedIDs: [String] = []
        var restored: String?
        let plan = plan(full: true, target: "q2", cut: "q2", prompt: "сделай X")
        let deps = RollbackChatApplier.Dependencies(
            messages: messages, sessionID: "s1",
            homeDirectory: FileManager.default.temporaryDirectory,
            removeMessage: { removedIDs.append($0) },
            appendMessage: { _ in },
            restorePrompt: { restored = $0 }
        )
        try RollbackChatApplier.apply(chip: chip(plan: plan), dependencies: deps)
        #expect(removedIDs == ["q2"])
        #expect(restored == "сделай X")
    }

    @Test("Откат к середине без promptRestore: промпт не трогается")
    func noPromptForMiddleRequest() throws {
        let messages = [message("q1"), message("a1", role: .assistant),
                        message("q2"), message("a2", role: .assistant)]
        var removedIDs: [String] = []
        var restored: String?
        let plan = plan(full: true, target: "q2", cut: "q2", prompt: nil)
        let deps = RollbackChatApplier.Dependencies(
            messages: messages, sessionID: "s1",
            homeDirectory: FileManager.default.temporaryDirectory,
            removeMessage: { removedIDs.append($0) },
            appendMessage: { _ in },
            restorePrompt: { restored = $0 }
        )
        try RollbackChatApplier.apply(chip: chip(plan: plan), dependencies: deps)
        #expect(removedIDs == ["a2"])
        #expect(restored == nil)
    }

    @Test("Архив создан в корзине при удалении сообщений")
    func archiveWrittenWhenTrimming() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollback-apply-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let messages = [message("q1"), message("a1", role: .assistant), message("q2")]
        let plan = plan(full: true, cut: "q1")
        let deps = RollbackChatApplier.Dependencies(
            messages: messages, sessionID: "s1", homeDirectory: home,
            removeMessage: { _ in }, appendMessage: { _ in }, restorePrompt: { _ in }
        )
        try RollbackChatApplier.apply(chip: chip(plan: plan), dependencies: deps)
        let dir = RollbackChatArchive.directory(homeDirectory: home)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(!files.isEmpty)
    }
}
