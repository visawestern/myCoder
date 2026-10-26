import Foundation

struct ProjectFileIndexSnapshot: Codable, Equatable {
    let projectPath: String
    let records: [FileIndexRecord]
}

enum ProjectFileIndexPersistenceLogic {
    static func encode(projectPath: String, records: [FileIndexRecord]) -> Data? {
        let snapshot = ProjectFileIndexSnapshot(projectPath: projectPath, records: records)
        return try? JSONEncoder().encode(snapshot)
    }

    static func decode(data: Data) -> ProjectFileIndexSnapshot? {
        try? JSONDecoder().decode(ProjectFileIndexSnapshot.self, from: data)
    }

    static func applyDelta(
        current: [FileIndexRecord],
        scanned: [FileIndexRecord]
    ) -> [FileIndexRecord] {
        var byPath = ProjectFileIndexLogic.recordsByPath(current)
        let scannedByPath = ProjectFileIndexLogic.recordsByPath(scanned)
        for path in scannedByPath.keys.sorted() {
            guard let record = scannedByPath[path] else { continue }
            if let existing = byPath[path],
               existing.hash == record.hash,
               existing.lastModified == record.lastModified {
                continue
            }
            byPath[path] = record
        }
        for path in byPath.keys where scannedByPath[path] == nil {
            byPath.removeValue(forKey: path)
        }
        return byPath.values.sorted { $0.path < $1.path }
    }
}

enum IndexingSettingsLogic {
    static let automaticIndexingIsAvailable = false
    static let statusMessage = "Automatic indexing is not available yet; @ file suggestions refresh on demand."
}
