import Testing
import Foundation
@testable import myCoder

/// The "no project" mode: a chat that is not tied to a project folder must
/// still have a real working directory, so tools and shell commands work.
@Suite("No-project mode")
struct ProjectlessWorkspaceTests {

    @Test("A project chat uses its project folder")
    func projectChatUsesProjectFolder() {
        let root = ProjectlessWorkspaceLogic.workingDirectory(
            sessionDirectory: "/Users/apple/projects/demo",
            workspacePath: "/Users/apple/projects/demo",
            homeDirectory: "/Users/apple"
        )
        #expect(root == "/Users/apple/projects/demo")
    }

    @Test("A project-less chat uses the home folder")
    func projectlessChatUsesHomeFolder() {
        let root = ProjectlessWorkspaceLogic.workingDirectory(
            sessionDirectory: ChatSession.standaloneProjectKey,
            workspacePath: ChatSession.standaloneProjectKey,
            homeDirectory: "/Users/apple"
        )
        #expect(root == "/Users/apple")
    }

    @Test("An open project-less chat keeps the home folder while a project is selected")
    func projectlessChatWinsOverSelectedProject() {
        let root = ProjectlessWorkspaceLogic.workingDirectory(
            sessionDirectory: ChatSession.standaloneProjectKey,
            workspacePath: "/Users/apple/projects/demo",
            homeDirectory: "/Users/apple"
        )
        #expect(root == "/Users/apple")
    }

    @Test("Without a chat the selected project is used")
    func noChatUsesSelectedProject() {
        let root = ProjectlessWorkspaceLogic.workingDirectory(
            sessionDirectory: nil,
            workspacePath: "/Users/apple/projects/demo",
            homeDirectory: "/Users/apple"
        )
        #expect(root == "/Users/apple/projects/demo")
    }

    @Test("Without a chat and without a project the home folder is used")
    func noChatNoProjectUsesHomeFolder() {
        let root = ProjectlessWorkspaceLogic.workingDirectory(
            sessionDirectory: nil,
            workspacePath: nil,
            homeDirectory: "/Users/apple"
        )
        #expect(root == "/Users/apple")
    }

    @Test("The synthetic workspace is recognized as project-less")
    func recognizesProjectlessWorkspace() {
        #expect(ProjectlessWorkspaceLogic.isProjectless(nil) == false)
        #expect(ProjectlessWorkspaceLogic.isProjectless(
            Workspace(id: "p1", name: "Demo", path: "/tmp/demo", tasks: [])
        ) == false)
        #expect(ProjectlessWorkspaceLogic.isProjectless(
            Workspace(id: ChatSession.standaloneProjectKey, name: "Chats", path: ChatSession.standaloneProjectKey, tasks: [])
        ) == true)
    }

    @MainActor
    @Test("Selecting the no-project mode switches the working directory to the home folder")
    func selectingNoProjectSwitchesWorkingDirectory() {
        let appState = AppState()
        appState.clearInMemoryState()

        appState.selectNoProject()

        #expect(appState.isProjectlessMode == true)
        #expect(appState.toolWorkingDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @MainActor
    @Test("A new chat without a project starts in the no-project mode")
    func projectlessTaskStartsInProjectlessMode() {
        let appState = AppState()
        appState.clearInMemoryState()

        appState.startProjectlessTask()

        #expect(appState.isProjectlessMode == true)
        #expect(appState.selectedSession == nil)
        #expect(appState.toolWorkingDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
    }
}
