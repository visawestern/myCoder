import Foundation
import Testing
@testable import myCoder

/// TDD for the chat→project upgrade (user directive 2026-11-13): the SAME
/// chat is bound to the project folder — same id/title/model/provider/history —
/// and the model is told to continue working there.
@Suite("Session→project bind — upgrade the current chat, keep chain")
struct SessionProjectBindLogicTests {

    private func makeStandaloneSession() -> ChatSession {
        ChatSession(
            id: "SESS-1",
            title: "попытка номер 4",
            directory: ChatSession.standaloneProjectKey,
            modelID: "mercury-3",
            providerID: "900B2DA9-13EA-4875-A7EE-38252D9AA35A"
        )
    }

    @Test("Bind keeps id/title/model/provider/history, changes only the folder")
    func bindKeepsIdentity() {
        let original = makeStandaloneSession()
        let bound = SessionProjectBindLogic.boundSession(original, to: "/Users/apple/projects/aquarium")

        #expect(bound.id == original.id)
        #expect(bound.title == original.title)
        #expect(bound.modelID == original.modelID)
        #expect(bound.providerID == original.providerID)
        #expect(bound.messages.count == original.messages.count)
        #expect(bound.directory == "/Users/apple/projects/aquarium")
        #expect(bound.directory != ChatSession.standaloneProjectKey)
    }

    @Test("Project id is the normalized path")
    func projectIDNormalized() {
        #expect(SessionProjectBindLogic.projectID(for: "/Users/apple/projects/aquarium/") == "/Users/apple/projects/aquarium")
    }

    @Test("Model notice names the folder and tells to continue")
    func modelNoticeContinuesInProject() {
        let notice = SessionProjectBindLogic.modelNotice(projectPath: "/Users/apple/projects/aquarium")
        #expect(notice.contains("/Users/apple/projects/aquarium"))
        #expect(notice.contains("Продолжай"))
        // Пунктуация/регистр в реальном тексте не критичны — проверяем
        // смысловую часть без учёта регистра.
        #expect(notice.lowercased().contains("не ищи файлы заново"))
    }

    @Test("UI notice names the project path")
    func uiNotice() {
        let notice = SessionProjectBindLogic.uiNotice(projectPath: "/Users/apple/projects/aquarium")
        #expect(notice.contains("/Users/apple/projects/aquarium"))
        #expect(notice.contains("Чат продолжает работать"))
    }
}
