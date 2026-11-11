import Testing
import Foundation
@testable import myCoder

/// The user must be able to CHANGE a goal: the title is edited in the
/// sidebar (and via `/goal edit`, the same path the API uses), and the change
/// is written to the same store the panel, the composer spoiler and the
/// verification read.
@MainActor
@Suite("Редактирование цели")
struct GoalEditingTests {

    private func home() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mycoder-goal-editing-\(UUID().uuidString)")
    }

    @Test("Пустое название отклоняется")
    func emptyTitleIsRejected() {
        #expect(GoalEditingLogic.normalizedTitle("   ") == nil)
        #expect(GoalEditingLogic.normalizedTitle("") == nil)
    }

    @Test("Название обрезается от пробелов и ограничивается по длине")
    func titleIsNormalized() {
        #expect(GoalEditingLogic.normalizedTitle("  Новая цель  ") == "Новая цель")
        let long = String(repeating: "я", count: GoalEditingLogic.maxTitleLength + 50)
        let normalized = GoalEditingLogic.normalizedTitle(long)
        #expect(normalized?.count == GoalEditingLogic.maxTitleLength)
    }

    @Test("Изменение названия сохраняется в хранилище")
    func updateTitlePersists() throws {
        let directory = home()
        defer { try? FileManager.default.removeItem(at: directory) }
        let goal = UserGoal(title: "Старая цель", state: .pending)
        try GoalStore.upsert(goal, homeDirectory: directory)

        #expect(try GoalStore.updateTitle(id: goal.id, title: "Новая цель", homeDirectory: directory))
        let loaded = GoalStore.load(homeDirectory: directory)
        #expect(loaded.count == 1)
        #expect(loaded.first?.title == "Новая цель")
    }

    @Test("Изменение неизвестной цели и пустого названия отклоняется")
    func updateRejectsUnknownAndEmpty() throws {
        let directory = home()
        defer { try? FileManager.default.removeItem(at: directory) }
        let goal = UserGoal(title: "Цель", state: .pending)
        try GoalStore.upsert(goal, homeDirectory: directory)

        #expect(try GoalStore.updateTitle(id: UUID(), title: "Что-то", homeDirectory: directory) == false)
        #expect(try GoalStore.updateTitle(id: goal.id, title: "  ", homeDirectory: directory) == false)
        #expect(GoalStore.load(homeDirectory: directory).first?.title == "Цель")
    }

    @Test("Команда /goal edit разбирается")
    func editCommandParses() {
        #expect(GoalCommandLogic.parse("/goal edit Новая цель") == .edit(title: "Новая цель"))
        #expect(GoalCommandLogic.parse("/goal EDIT  Другая цель ") == .edit(title: "Другая цель"))
        // Пустое содержимое — не команда редактирования, а список целей.
        #expect(GoalCommandLogic.parse("/goal edit") == .list)
    }

    @Test("Сервис цели применяет правку и отвечает")
    func serviceAppliesEdit() throws {
        let directory = home()
        defer { try? FileManager.default.removeItem(at: directory) }
        let goal = UserGoal(title: "Старая цель", state: .pending)
        try GoalStore.upsert(goal, homeDirectory: directory)

        let result = try GoalService.apply(.edit(title: "Новая цель"),
                                           homeDirectory: directory,
                                           language: .russian)
        #expect(GoalStore.load(homeDirectory: directory).first?.title == "Новая цель")
        #expect(result.reply.contains("Новая цель"))
    }

    @Test("Правка без цели честно сообщает, что цели нет")
    func editWithoutGoal() throws {
        let directory = home()
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try GoalService.apply(.edit(title: "Новая цель"),
                                           homeDirectory: directory,
                                           language: .russian)
        #expect(result.goals.isEmpty)
        #expect(!result.reply.isEmpty)
    }
}
