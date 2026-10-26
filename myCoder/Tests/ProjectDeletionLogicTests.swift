import Foundation
import Testing
@testable import myCoder

@Suite("Project deletion planning")
struct ProjectDeletionLogicTests {
    @Test("deletion work is split into bounded chunks")
    func chunksAreBounded() {
        let chunks = ProjectDeletionLogic.chunks(for: Array(1...5), chunkSize: 2)
        #expect(chunks == [[1, 2], [3, 4], [5]])
    }

    @Test("progress is clamped and reports completion")
    func progressIsSafe() {
        #expect(ProjectDeletionLogic.progress(completed: 0, total: 4) == 0)
        #expect(ProjectDeletionLogic.progress(completed: 2, total: 4) == 0.5)
        #expect(ProjectDeletionLogic.progress(completed: 9, total: 4) == 1)
        #expect(ProjectDeletionLogic.progress(completed: 1, total: 0) == 1)
    }

    @Test("root and empty paths cannot produce a deletion plan")
    func rootIsRejected() {
        #expect(ProjectDeletionLogic.canDeleteProjectData(at: "" ) == false)
        #expect(ProjectDeletionLogic.canDeleteProjectData(at: "/") == false)
    }
}
