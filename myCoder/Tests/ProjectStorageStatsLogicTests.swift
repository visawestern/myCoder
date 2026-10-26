import Testing
@testable import myCoder

@Suite("Project storage statistics")
struct ProjectStorageStatsLogicTests {
    @Test("aggregates project databases with legacy global statistics")
    func aggregatesProjectStats() {
        let result = ProjectStorageStatsLogic.aggregate(
            global: .init(databaseSize: 100, messageCount: 2, active: 1, archived: 1, projectID: "legacy"),
            projects: [
                .init(databaseSize: 300, messageCount: 5, active: 2, archived: 1, projectID: "/tmp/a"),
                .init(databaseSize: 200, messageCount: 3, active: 1, archived: 0, projectID: "/tmp/b")
            ],
            snapshotSize: 50
        )
        #expect(result.databaseSize == 600)
        #expect(result.messageCount == 10)
        #expect(result.snapshotSize == 50)
        #expect(result.sessionCounts == [
            .init(projectID: "legacy", active: 1, archived: 1),
            .init(projectID: "/tmp/a", active: 2, archived: 1),
            .init(projectID: "/tmp/b", active: 1, archived: 0)
        ])
    }

    @Test("does not duplicate a project snapshot when the same path is loaded twice")
    func deDuplicatesProjectSnapshots() {
        let result = ProjectStorageStatsLogic.aggregate(
            global: .init(databaseSize: 0, messageCount: 0, active: 0, archived: 0, projectID: "legacy"),
            projects: [
                .init(databaseSize: 100, messageCount: 1, active: 1, archived: 0, projectID: "/tmp/a"),
                .init(databaseSize: 100, messageCount: 1, active: 1, archived: 0, projectID: "/tmp/a")
            ],
            snapshotSize: 0
        )
        #expect(result.databaseSize == 100)
        #expect(result.messageCount == 1)
        #expect(result.sessionCounts.count == 2)
    }
}
