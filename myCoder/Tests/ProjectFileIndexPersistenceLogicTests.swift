import Foundation
import Testing
@testable import myCoder

@Suite("Persistent project file index")
struct ProjectFileIndexPersistenceLogicTests {
    private func record(_ path: String, hash: String, mtime: TimeInterval = 1) -> FileIndexRecord {
        FileIndexRecord(path: path, hash: hash, size: 10, lastModified: mtime, language: "swift")
    }

    @Test("snapshot round-trips records for one project")
    func snapshotRoundTrip() throws {
        let records = [record("Sources/App.swift", hash: "a")]
        let data = try #require(ProjectFileIndexPersistenceLogic.encode(projectPath: "/tmp/project", records: records))
        let snapshot = try #require(ProjectFileIndexPersistenceLogic.decode(data: data))
        #expect(snapshot.projectPath == "/tmp/project")
        #expect(snapshot.records == records)
    }

    @Test("applyDelta replaces changed records and removes deleted records")
    func deltaApplication() {
        let current = [record("old.swift", hash: "old"), record("keep.swift", hash: "same")]
        let scanned = [record("keep.swift", hash: "same"), record("new.swift", hash: "new")]
        let result = ProjectFileIndexPersistenceLogic.applyDelta(current: current, scanned: scanned)
        #expect(result == scanned)
    }

    @Test("indexing settings expose honest availability")
    func settingsAvailability() {
        #expect(!IndexingSettingsLogic.automaticIndexingIsAvailable)
        #expect(IndexingSettingsLogic.statusMessage.contains("not available"))
    }
}
