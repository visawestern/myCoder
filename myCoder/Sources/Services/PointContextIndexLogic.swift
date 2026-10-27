import Foundation

/// Guarantees the send path has a project index to compile from.
///
/// The index is otherwise built lazily, when the user opens the `@` picker or
/// searches project files. Point context must not silently do nothing until
/// then, so the first send with an empty index scans the project once and
/// persists the result.
enum PointContextIndexLogic {

    static func records(projectPath: String,
                        load: (String) -> [FileIndexRecord] = { ProjectFileIndexStore.load(projectPath: $0) },
                        scan: (String) -> [FileIndexRecord] = { ProjectFileScanner.scan(root: $0) },
                        save: (String, [FileIndexRecord]) -> Void = {
                            ProjectFileIndexStore.save(projectPath: $0, records: $1)
                        }) -> [FileIndexRecord] {
        guard !projectPath.isEmpty else { return [] }
        let stored = load(projectPath)
        guard stored.isEmpty else { return stored }
        let scanned = scan(projectPath)
        guard !scanned.isEmpty else { return [] }
        let records = ProjectFileIndexPersistenceLogic.applyDelta(current: [], scanned: scanned)
        save(projectPath, records)
        return records
    }
}
