import Foundation

/// Адаптеры реального окружения для отката: восстановление из снапшотов
/// (проектных или глобальных), корзина, пометка undo-записей и загрузка
/// истории изменений сессии.

/// Восстановление файлов из снапшотов: проектные (`ProjectSnapshotManager`),
/// если известен путь проекта, иначе глобальные (`FileSnapshotManager`).
struct RollbackSnapshotRestorer: RollbackSnapshotRestoring {
    let projectPath: String?

    func restoreFromSnapshot(snapshotId: String) throws {
        if let projectPath,
           let manager = try? ProjectSnapshotManager(projectPath: projectPath) {
            try manager.restoreFromSnapshot(snapshotId: snapshotId)
        } else {
            try FileSnapshotManager.shared.restoreFromSnapshot(snapshotId: snapshotId)
        }
    }
}

/// Корзина: копия текущего файла перед восстановлением сохраняется в
/// `~/.mycoder/deleted-backups/rollback-files/` — ничего не удаляется
/// насовсем.
struct RollbackTrashStore: RollbackTrashStoring {
    let homeDirectory: URL

    func storeCopy(ofFileAt path: String, scope: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let dir = ProjectAutoBackupLogic.deletedBackupsDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("rollback-files", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString)-\(URL(fileURLWithPath: path).lastPathComponent)"
        let destination = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(atPath: path, toPath: destination.path)
        return destination.path
    }
}

/// Пометка undo-записи использованной: проектная БД — через
/// `markUndoEntryUsed`, глобальная — SQL-обновлением.
struct RollbackUndoMarker: RollbackUndoMarking {
    let projectPath: String?

    func markUndoEntryUsed(id: String) throws {
        if let projectPath,
           let manager = try? ProjectUndoManager(projectPath: projectPath) {
            try manager.db.markUndoEntryUsed(id: id)
        } else {
            let escaped = id.replacingOccurrences(of: "'", with: "''")
            try DatabaseManager.shared.exec(
                "UPDATE undo_stack SET can_undo = 0 WHERE id = '\(escaped)'"
            )
        }
    }
}

/// Загрузка истории изменений сессии для планирования отката.
enum RollbackUndoLoader {

    static func load(sessionID: String,
                     projectPath: String?,
                     homeDirectory: URL) -> [RollbackUndoEntryRef] {
        if let projectPath,
           let manager = try? ProjectUndoManager(projectPath: projectPath),
           let records = try? manager.history(sessionId: sessionID) {
            return records.compactMap { Self.ref(from: $0) }
        }
        // Глобальная БД: список снапшотов сессии.
        return UndoRedoManager.shared.history(sessionId: sessionID)
            .compactMap { Self.ref(globalRow: $0, sessionID: sessionID) }
    }

    /// Преобразование проектной записи.
    static func ref(from record: ProjectUndoEntryRecord) -> RollbackUndoEntryRef? {
        guard let path = record.targetPath else { return nil }
        return RollbackUndoEntryRef(
            id: record.id,
            path: path,
            snapshotID: record.snapshotId,
            actionType: record.actionType,
            canUndo: record.canUndo,
            createdAt: record.createdAt.timeIntervalSince1970
        )
    }

    /// Преобразование строки глобальной истории (снапшот).
    static func ref(globalRow row: [String: Any], sessionID: String) -> RollbackUndoEntryRef? {
        guard let snapshotId = row["snapshotId"] as? String,
              let filePath = row["filePath"] as? String,
              let rowSession = row["sessionId"] as? String,
              rowSession == sessionID else { return nil }
        let operation = row["operation"] as? String ?? ""
        let timestamp = row["timestamp"] as? Double ?? 0
        return RollbackUndoEntryRef(
            id: snapshotId,
            path: filePath,
            snapshotID: snapshotId,
            actionType: operation,
            canUndo: true,
            createdAt: timestamp
        )
    }
}
