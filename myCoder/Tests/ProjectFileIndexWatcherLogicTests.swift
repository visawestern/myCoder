import Foundation
import Testing
@testable import myCoder

@Suite("Project file index watcher")
struct ProjectFileIndexWatcherLogicTests {
    @Test("a changed file inside the active project invalidates the index")
    func projectFileInvalidates() {
        #expect(ProjectFileIndexWatcherLogic.shouldInvalidate(
            changedPath: "/tmp/project/Sources/App.swift",
            projectPath: "/tmp/project"
        ))
    }

    @Test("unrelated paths and the index snapshot itself do not invalidate")
    func unrelatedPathsIgnored() {
        #expect(!ProjectFileIndexWatcherLogic.shouldInvalidate(
            changedPath: "/tmp/other/App.swift",
            projectPath: "/tmp/project"
        ))
        #expect(!ProjectFileIndexWatcherLogic.shouldInvalidate(
            changedPath: "/tmp/project/.mycoder/file_index.json",
            projectPath: "/tmp/project"
        ))
    }

    @Test("stale watcher callbacks cannot update a switched project")
    func staleGenerationRejected() {
        #expect(ProjectFileIndexWatcherLogic.shouldApply(
            eventProjectPath: "/tmp/project-b",
            activeProjectPath: "/tmp/project-b",
            eventGeneration: 2,
            activeGeneration: 2
        ))
        #expect(!ProjectFileIndexWatcherLogic.shouldApply(
            eventProjectPath: "/tmp/project-a",
            activeProjectPath: "/tmp/project-b",
            eventGeneration: 1,
            activeGeneration: 2
        ))
    }

    @Test("watcher exposes a bounded debounce interval")
    func debounceIsBounded() {
        #expect(ProjectFileIndexWatcherLogic.debounceNanoseconds > 0)
        #expect(ProjectFileIndexWatcherLogic.debounceNanoseconds <= 1_000_000_000)
    }
}
