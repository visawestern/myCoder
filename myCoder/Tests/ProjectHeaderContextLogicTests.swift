import Testing
@testable import myCoder

@Suite("Project header context")
struct ProjectHeaderContextLogicTests {
    @Test("active workspace drives branch visibility after project model migration")
    func workspaceDrivesBranchVisibility() {
        #expect(ProjectHeaderContextLogic.shouldShowBranch(
            selectedWorkspace: true,
            selectedLegacyProject: false
        ))
    }

    @Test("header hides branch when no project context exists")
    func noProjectHidesBranch() {
        #expect(!ProjectHeaderContextLogic.shouldShowBranch(
            selectedWorkspace: false,
            selectedLegacyProject: false
        ))
    }
}
