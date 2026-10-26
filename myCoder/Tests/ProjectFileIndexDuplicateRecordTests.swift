import Foundation
import Testing
@testable import myCoder

@Suite("STO-06 duplicate file-index records")
struct ProjectFileIndexDuplicateRecordTests {
    private func record(_ path: String, hash: String, mtime: TimeInterval = 1) -> FileIndexRecord {
        FileIndexRecord(path: path, hash: hash, size: 10, lastModified: mtime, language: "swift")
    }

    @Test("computeDelta deduplicates duplicate current and scanned paths")
    func computeDeltaIsResilientToDuplicates() {
        let delta = ProjectFileIndexLogic.computeDelta(
            current: [record("A.swift", hash: "old"), record("A.swift", hash: "new")],
            scanned: [record("A.swift", hash: "new"), record("A.swift", hash: "latest")]
        )
        #expect(delta.toUpsert == [record("A.swift", hash: "latest")])
        #expect(delta.toRemove.isEmpty)
    }

    @Test("applyDelta deduplicates persisted duplicate paths")
    func applyDeltaIsResilientToDuplicates() {
        let result = ProjectFileIndexPersistenceLogic.applyDelta(
            current: [record("A.swift", hash: "old"), record("A.swift", hash: "new")],
            scanned: [record("A.swift", hash: "latest"), record("B.swift", hash: "b")]
        )
        #expect(result == [record("A.swift", hash: "latest"), record("B.swift", hash: "b")])
    }
}
