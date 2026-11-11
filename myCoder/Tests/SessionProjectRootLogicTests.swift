import Testing
import Foundation
@testable import myCoder

/// The context collection must use the project of the OPEN CHAT, not the
/// globally selected workspace. Live check 2026-11-08: a chat about the
/// myCoder project collected context from the selected llama.cpp workspace —
/// the model answered about the wrong project (its AGENTS.md, files, plan).
/// The session owns its project (`ChatSession.directory`); the workspace is
/// only a fallback for chats without one (e.g. brand-new sessions).
@MainActor
@Suite("Корень проекта для сбора контекста")
struct SessionProjectRootLogicTests {

    @Test("Проект сессии имеет приоритет над выбранным workspace")
    func sessionWins() {
        let root = SessionProjectRootLogic.resolve(
            sessionDirectory: "/Users/apple/projects/myCoder",
            selectedWorkspacePath: "/Users/apple/llamacpp/llama-metal-glimmer"
        )
        #expect(root == "/Users/apple/projects/myCoder")
    }

    @Test("Standalone-чат (без проекта) использует выбранный workspace")
    func standaloneFallsBackToWorkspace() {
        let root = SessionProjectRootLogic.resolve(
            sessionDirectory: ChatSession.standaloneProjectKey,
            selectedWorkspacePath: "/Users/apple/projects/myCoder"
        )
        #expect(root == "/Users/apple/projects/myCoder")
    }

    @Test("Пустой project сессии — фолбэк на workspace (новый чат)")
    func emptySessionFallsBackToWorkspace() {
        let root = SessionProjectRootLogic.resolve(
            sessionDirectory: "",
            selectedWorkspacePath: "/Users/apple/projects/myCoder"
        )
        #expect(root == "/Users/apple/projects/myCoder")
    }

    @Test("Нет ни сессии, ни workspace — пустой корень (чат без проекта)")
    func nothingResolvesToEmpty() {
        let root = SessionProjectRootLogic.resolve(sessionDirectory: nil, selectedWorkspacePath: nil)
        #expect(root.isEmpty)
    }

    @Test("Проект сессии обрезается, но не ломается")
    func sessionPathIsTrimmed() {
        let root = SessionProjectRootLogic.resolve(
            sessionDirectory: "  /Users/apple/projects/myCoder  ",
            selectedWorkspacePath: "/Users/apple/llamacpp/llama-metal-glimmer"
        )
        #expect(root == "/Users/apple/projects/myCoder")
    }
}
