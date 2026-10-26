import Foundation

final class ProjectFileIndexStore {
    static func load(projectPath: String, fileManager: FileManager = .default) -> [FileIndexRecord] {
        let url = ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath)
            .appendingPathComponent("file_index.json")
        guard let data = try? Data(contentsOf: url),
              let snapshot = ProjectFileIndexPersistenceLogic.decode(data: data),
              snapshot.projectPath == projectPath else { return [] }
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
        try? data.write(to: directory.appendingPathComponent("file_index.json"), options: .atomic)
    }
}
