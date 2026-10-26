import Foundation
import Testing
@testable import myCoder

@Suite("STO-07 watcher lifecycle")
struct ProjectFileIndexWatcherLifecycleLogicTests {
    @Test("branch-only workspace mutation does not restart watcher")
    func sameProjectPathDoesNotRestart() {
        #expect(!ProjectFileIndexWatcherLifecycleLogic.shouldRestart(
            oldProjectPath: "/tmp/project/",
            newProjectPath: "/tmp/project"
        ))
    }

    @Test("switching project paths restarts watcher")
    func changedProjectPathRestarts() {
        #expect(ProjectFileIndexWatcherLifecycleLogic.shouldRestart(
            oldProjectPath: "/tmp/project-a",
            newProjectPath: "/tmp/project-b"
        ))
    }

    @Test("creating or clearing a workspace restarts watcher")
    func nilTransitionsRestart() {
        #expect(ProjectFileIndexWatcherLifecycleLogic.shouldRestart(oldProjectPath: nil, newProjectPath: "/tmp/project"))
        #expect(ProjectFileIndexWatcherLifecycleLogic.shouldRestart(oldProjectPath: "/tmp/project", newProjectPath: nil))
    }
}
