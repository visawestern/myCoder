import Foundation

final class ProjectFileIndexStore {
    /// A big repo's snapshot can be hundreds of MB of JSON; decoding it on
    /// every context build froze sends for minutes (observed: 17.5k records
    /// → 122 MB → ~60s+ of JSONDecoder per send). Cache the decoded snapshot
    /// per project and reload only when the file on disk changes.
    private struct Entry {
        let modified: Date
        let records: [FileIndexRecord]
    }

    private static let lock = NSLock()
    private static var cache: [String: Entry] = [:]

    static func load(projectPath: String, fileManager: FileManager = .default) -> [FileIndexRecord] {
        let url = ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath)
            .appendingPathComponent("file_index.json")
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return [] }

        lock.lock()
        if let entry = cache[url.path], entry.modified == modified {
            let records = entry.records
            lock.unlock()
            return records
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: url),
              let snapshot = ProjectFileIndexPersistenceLogic.decode(data: data),
              snapshot.projectPath == projectPath else { return [] }

        lock.lock()
        cache[url.path] = Entry(modified: modified, records: snapshot.records)
        lock.unlock()
        return snapshot.records
    }

    static func save(
        projectPath: String,
        records: [FileIndexRecord],
        fileManager: FileManager = .default
    ) {
        guard !projectPath.isEmpty,
              let data = ProjectFileIndexPersistenceLogic.encode(projectPath: projectPath, records: records) else { return }
        let directory = ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("file_index.json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }

        let modified = ((try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? Date()
        lock.lock()
        cache[url.path] = Entry(modified: modified, records: records)
        lock.unlock()
    }
}
