import Testing
import Foundation
@testable import myCoder

/// ЦЕЛЬ привязана к чату/проекту (директива 2026-11-08): одна и та же цель
/// больше не «висит» в сайдбаре и не мигрирует между чатами. Чат видит свои
/// цели и цели своего проекта; цель другого чата/проекта не видна.
@MainActor
@Suite("ЦЕЛЬ — привязка к чату и проекту")
struct GoalContextLogicTests {

    private func goal(title: String,
                      chatID: String? = nil,
                      projectPath: String? = nil) -> UserGoal {
        UserGoal(title: title, projectPath: projectPath, chatID: chatID)
    }

    // MARK: - Фильтрация

    @Test("Цель чата видна только в этом чате")
    func chatGoalIsScopedToItsChat() {
        let g = goal(title: "Чат A", chatID: "chat-a")
        #expect(GoalContextLogic.matches(g, context: GoalContext(chatID: "chat-a", projectPath: "/p")))
        #expect(!GoalContextLogic.matches(g, context: GoalContext(chatID: "chat-b", projectPath: "/p")))
        #expect(!GoalContextLogic.matches(g, context: GoalContext(chatID: nil, projectPath: "/p")))
    }

    @Test("Цель проекта видна в любом чате этого проекта")
    func projectGoalIsVisibleInProjectChats() {
        let g = goal(title: "Проект", projectPath: "/p")
        #expect(GoalContextLogic.matches(g, context: GoalContext(chatID: "chat-a", projectPath: "/p")))
        #expect(GoalContextLogic.matches(g, context: GoalContext(chatID: "chat-b", projectPath: "/p")))
        #expect(!GoalContextLogic.matches(g, context: GoalContext(chatID: "chat-a", projectPath: "/other")))
    }

    @Test("Старая цель без привязки видна только вне чата и проекта")
    func legacyGoalOnlyInEmptyContext() {
        let g = goal(title: "Старая")
        #expect(GoalContextLogic.matches(g, context: GoalContext()))
        #expect(!GoalContextLogic.matches(g, context: GoalContext(chatID: "chat-a", projectPath: nil)))
        #expect(!GoalContextLogic.matches(g, context: GoalContext(chatID: nil, projectPath: "/p")))
    }

    @Test("В чате проекта видны и его цели, и цели проекта, и ничего чужого")
    func visibleGoalsCombinesScopes() {
        let all = [
            goal(title: "Своя", chatID: "chat-a", projectPath: "/p"),
            goal(title: "Проектная", projectPath: "/p"),
            goal(title: "Чужая", chatID: "chat-b", projectPath: "/p"),
            goal(title: "Другой проект", projectPath: "/other"),
            goal(title: "Старая"),
        ]
        let visible = GoalContextLogic.visibleGoals(
            all,
            context: GoalContext(chatID: "chat-a", projectPath: "/p")
        )
        #expect(visible.map(\.title) == ["Своя", "Проектная"])
    }

    @Test("Standalone-чат не наследует цели выбранного проекта")
    func standaloneChatDoesNotInheritProjectGoals() {
        let context = GoalContextLogic.context(
            chatID: "standalone-chat",
            sessionDirectory: ChatSession.standaloneProjectKey,
            selectedWorkspacePath: "/p"
        )
        #expect(context.chatID == "standalone-chat")
        #expect(context.projectPath == nil)
        let visible = GoalContextLogic.visibleGoals(
            [goal(title: "Проектная", projectPath: "/p")],
            context: context
        )
        #expect(visible.isEmpty)
    }

    // MARK: - Контекст из состояния приложения

    @Test("Проект сессии приоритетнее выбранного workspace")
    func contextPrefersSessionProject() {
        let context = GoalContextLogic.context(
            chatID: "chat-a",
            sessionDirectory: "/Users/apple/projects/myCoder",
            selectedWorkspacePath: "/Users/apple/llamacpp/llama-metal-glimmer"
        )
        #expect(context.chatID == "chat-a")
        #expect(context.projectPath == "/Users/apple/projects/myCoder")
    }

    @Test("Без сессии проект — выбранный workspace")
    func contextFallsBackToWorkspace() {
        let context = GoalContextLogic.context(
            chatID: nil,
            sessionDirectory: nil,
            selectedWorkspacePath: "/Users/apple/projects/myCoder"
        )
        #expect(context.projectPath == "/Users/apple/projects/myCoder")
        #expect(context.chatID == nil)
    }

    @Test("Пути нормализуются: пробелы обрезаются, пустое — nil")
    func contextNormalizesPaths() {
        let context = GoalContextLogic.context(
            chatID: "  chat-a  ",
            sessionDirectory: "   ",
            selectedWorkspacePath: "  "
        )
        #expect(context.chatID == "chat-a")
        #expect(context.projectPath == nil)
    }

    // MARK: - Сервис: создание и действия в контексте

    @Test("Созданная цель привязывается к чату и проекту")
    func createBindsGoalToContext() throws {
        let h = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: h) }
        let context = GoalContext(chatID: "chat-a", projectPath: "/p")
        let result = try GoalService.apply(
            .create(title: "Цель"), homeDirectory: h, language: .russian, context: context
        )
        #expect(result.goals.first?.chatID == "chat-a")
        #expect(result.goals.first?.projectPath == "/p")
    }

    @Test("Start выбирает цель текущего чата, а не последнюю глобальную")
    func startTargetsCurrentChatGoal() throws {
        let h = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: h) }
        let contextA = GoalContext(chatID: "chat-a", projectPath: "/p")
        let contextB = GoalContext(chatID: "chat-b", projectPath: "/p")
        _ = try GoalService.apply(.create(title: "Цель A"), homeDirectory: h, language: .russian, context: contextA)
        _ = try GoalService.apply(.create(title: "Цель B"), homeDirectory: h, language: .russian, context: contextB)
        _ = try GoalService.apply(.start, homeDirectory: h, language: .russian, context: contextA)
        let goals = GoalStore.load(homeDirectory: h)
        #expect(goals.first(where: { $0.title == "Цель A" })?.state == .active)
        #expect(goals.first(where: { $0.title == "Цель B" })?.state == .pending)
    }

    @Test("List показывает только цели текущего контекста")
    func listIsScopedToContext() throws {
        let h = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: h) }
        _ = try GoalService.apply(.create(title: "Своя"), homeDirectory: h, language: .russian,
                                  context: GoalContext(chatID: "chat-a", projectPath: "/p"))
        _ = try GoalService.apply(.create(title: "Чужая"), homeDirectory: h, language: .russian,
                                  context: GoalContext(chatID: "chat-b", projectPath: "/p"))
        let list = try GoalService.apply(.list, homeDirectory: h, language: .russian,
                                         context: GoalContext(chatID: "chat-a", projectPath: "/p"))
        #expect(list.reply.contains("Своя"))
        #expect(!list.reply.contains("Чужая"))
    }

    @Test("Legacy-цель (без привязки) по-прежнему видна вне контекста")
    func legacyGoalStillReachable() throws {
        let h = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: h) }
        _ = try GoalService.apply(.create(title: "Старая"), homeDirectory: h, language: .russian)
        let list = try GoalService.apply(.list, homeDirectory: h, language: .russian)
        #expect(list.reply.contains("Старая"))
    }
}
