import Testing
import Foundation
@testable import myCoder

/// `/api/send` without a `chatId` always created a *standalone* chat, even when
/// a project was open. A standalone chat's working directory is the home
/// folder, so the system prompt told the model `cwd: /Users/apple` while the
/// compiled context listed project files — the model then answered "the project
/// is not in the current directory" and went hunting across the whole disk
/// (live run 2026-11-03). The send target must follow the open project.
@Suite("Цель отправки следует за открытым проектом")
struct SendTargetProjectTests {

    private let project = Workspace(
        id: "/Users/x/proj",
        name: "proj",
        path: "/Users/x/proj",
        tasks: []
    )

    private let standalone = Workspace(
        id: ChatSession.standaloneProjectKey,
        name: "Chats",
        path: ChatSession.standaloneProjectKey,
        tasks: []
    )

    @Test("Открыт проект — новый чат проектный, рабочий каталог = проект")
    func openProjectCreatesProjectChat() {
        let plan = SendTargetPlanLogic.plan(chatId: nil, selectedWorkspace: project)
        #expect(plan.createsStandalone == false)
        #expect(plan.workspacePath == "/Users/x/proj")
        #expect(plan.workingDirectory == "/Users/x/proj")
    }

    @Test("Режим без проекта — чат standalone, рабочий каталог = домашний")
    func projectlessCreatesStandaloneChat() {
        let plan = SendTargetPlanLogic.plan(chatId: nil, selectedWorkspace: standalone)
        #expect(plan.createsStandalone == true)
        #expect(plan.workspacePath == ChatSession.standaloneProjectKey)
        #expect(plan.workingDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @Test("Нет выбранного workspace — честный standalone")
    func noWorkspaceIsStandalone() {
        let plan = SendTargetPlanLogic.plan(chatId: nil, selectedWorkspace: nil)
        #expect(plan.createsStandalone == true)
    }

    @Test("Существующий chatId не создаёт новый чат")
    func existingChatIsReused() {
        let plan = SendTargetPlanLogic.plan(chatId: "abc", selectedWorkspace: project)
        #expect(plan.createsStandalone == false)
        #expect(plan.reusesChatId == "abc")
    }

    @Test("Пустой chatId считается отсутствующим")
    func emptyChatIdIsAbsent() {
        let plan = SendTargetPlanLogic.plan(chatId: "", selectedWorkspace: project)
        #expect(plan.reusesChatId == nil)
        #expect(plan.createsStandalone == false)
    }
}
