import Foundation

final class ProjectDeletionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

final class ProjectDeletionProgress: @unchecked Sendable {
    struct Snapshot: Sendable {
        let completed: Int
        let total: Int
        let finished: Bool
    }

    private let lock = NSLock()
    private var completed = 0
    private var total = 0
    private var finished = false

    func update(completed: Int, total: Int) {
        lock.lock()
        self.completed = completed
        self.total = total
        lock.unlock()
    }

    func finish() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(completed: completed, total: total, finished: finished)
    }
}

enum ProjectDeletionExecutor {
    @discardableResult
    static func deleteProjectData(
        projectPath: String,
        fileManager: FileManager = .default
    ) -> Bool {
        if case .completed = execute(projectPath: projectPath, fileManager: fileManager) {
            return true
        }
        return false
    }

    static func execute(
        projectPath: String,
        fileManager: FileManager = .default,
        shouldCancel: () -> Bool = { false },
        onProgress: (Int, Int) -> Void = { _, _ in }
    ) -> ProjectDeletionOutcomeLogic.Outcome {
        guard ProjectDeletionLogic.canDeleteProjectData(at: projectPath) else {
            return .failed("The project path is empty or unsafe.")
        }
        let root = ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath).standardizedFileURL
        let projectRoot = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        guard root.path.hasPrefix(projectRoot + "/") else {
            return .failed("The project data path is outside the selected project.")
        }
        return removeContents(
            of: root,
            fileManager: fileManager,
            shouldCancel: shouldCancel,
            onProgress: onProgress
        )
    }

    private static func removeContents(
        of root: URL,
        fileManager: FileManager,
        shouldCancel: () -> Bool,
        onProgress: (Int, Int) -> Void
    ) -> ProjectDeletionOutcomeLogic.Outcome {
        guard fileManager.fileExists(atPath: root.path) else { return .completed }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return .failed("The project data directory could not be enumerated.")
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            urls.append(url)
        }
        let filesFirst = urls.sorted { lhs, rhs in
            lhs.pathComponents.count > rhs.pathComponents.count
        }
        let total = filesFirst.count
        var completed = 0
        onProgress(completed, total)

        for chunk in ProjectDeletionLogic.chunks(for: filesFirst) {
            if shouldCancel() {
                return .cancelled(completed: completed, total: total)
            }
            for url in chunk {
                if shouldCancel() {
                    return .cancelled(completed: completed, total: total)
                }
                do {
                    try fileManager.removeItem(at: url)
                    completed += 1
                    onProgress(completed, total)
                } catch {
                    return .failed("Could not remove \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        do {
            try fileManager.removeItem(at: root)
        } catch {
            return .failed("Could not remove the project data directory: \(error.localizedDescription)")
        }
        guard !fileManager.fileExists(atPath: root.path) else {
            return .failed("The project data directory still exists after deletion.")
        }
        return .completed
    }
}
