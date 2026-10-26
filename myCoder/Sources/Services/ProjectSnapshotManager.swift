import Foundation

/// Per-project counterpart to the legacy global `FileSnapshotManager`.
/// Stores file snapshots under `<project>/.mycoder/snapshots/` instead of
/// the shared `~/.mycoder/snapshots/`, so a project's rollback history
/// lives (and travels) with the project instead of being mixed together
/// with every other project's snapshots in one global folder.
final class ProjectSnapshotManager {
    let projectPath: String
    private let snapshotsBasePath: String
    private let fileManager = FileManager.default

    init(projectPath: String) throws {
        let normalized = ChatSession.normalizedPath(projectPath)
        var isDirectory: ObjCBool = false
        guard normalized.hasPrefix("/"),
              fileManager.fileExists(atPath: normalized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectDatabaseError.projectDirectoryNotFound(normalized)
        }
        self.projectPath = normalized
        let snapshotsDir = MyCoderPaths.snapshotsDir(projectPath: normalized)
        try fileManager.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        self.snapshotsBasePath = snapshotsDir.path
    }

    /// Saves a snapshot of `path` immediately before it is modified.
    /// - Returns: an id that can later be passed to `restoreFromSnapshot`.
    @discardableResult
    func snapshotFile(at path: String, operation: String, sessionId: String) throws -> String {
        let snapshotId = "\(sessionId)_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
        let snapshotDir = "\(snapshotsBasePath)/\(snapshotId)"
        try fileManager.createDirectory(atPath: snapshotDir, withIntermediateDirectories: true)

        let existed = fileManager.fileExists(atPath: path)
        if existed {
            let content = try Data(contentsOf: URL(fileURLWithPath: path))
            try content.write(to: URL(fileURLWithPath: "\(snapshotDir)/original"))

            let meta: [String: Any] = [
                "filePath": path,
                "operation": operation,
                "timestamp": Date().timeIntervalSince1970,
                "sessionId": sessionId,
                "fileSize": content.count,
                "existed": true
            ]
            let metaData = try JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted)
            try metaData.write(to: URL(fileURLWithPath: "\(snapshotDir)/metadata.json"))
        } else {
            // The file did not exist before the operation; undo must restore
            // that "absent" state (i.e. delete the created file).
            let meta: [String: Any] = [
                "filePath": path,
                "operation": operation,
                "timestamp": Date().timeIntervalSince1970,
                "sessionId": sessionId,
                "existed": false
            ]
            let metaData = try JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted)
            try metaData.write(to: URL(fileURLWithPath: "\(snapshotDir)/metadata.json"))
        }

        return snapshotId
    }

    func restoreFromSnapshot(snapshotId: String) throws {
        let snapshotDir = "\(snapshotsBasePath)/\(snapshotId)"
        let originalPath = "\(snapshotDir)/original"
        let metaPath = "\(snapshotDir)/metadata.json"

        guard fileManager.fileExists(atPath: metaPath) else {
            throw SnapshotError.snapshotNotFound
        }

        let metaData = try Data(contentsOf: URL(fileURLWithPath: metaPath))
        guard let meta = try JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let filePath = meta["filePath"] as? String else {
            throw SnapshotError.invalidMetadata
        }

        // Restore the pre-operation state: if the file did not exist before
        // the operation, undo deletes the created file instead of restoring
        // content (there is none).
        if let existed = meta["existed"] as? Bool, !existed {
            if fileManager.fileExists(atPath: filePath) {
                try fileManager.removeItem(atPath: filePath)
            }
            return
        }

        guard fileManager.fileExists(atPath: originalPath) else {
            throw SnapshotError.snapshotNotFound
        }
        let originalContent = try Data(contentsOf: URL(fileURLWithPath: originalPath))
        try originalContent.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }

    func deleteSnapshot(snapshotId: String) {
        let snapshotDir = "\(snapshotsBasePath)/\(snapshotId)"
        try? fileManager.removeItem(atPath: snapshotDir)
    }

    func snapshotsSizeBytes() -> UInt64 {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: snapshotsBasePath) else { return 0 }
        var total: UInt64 = 0
        for item in contents {
            let itemPath = "\(snapshotsBasePath)/\(item)"
            guard let attrs = try? fileManager.attributesOfItem(atPath: itemPath),
                  let size = attrs[.size] as? UInt64 else { continue }
            total += size
        }
        return total
    }
}
