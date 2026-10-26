import Foundation

/// Менеджер снимков файлов для системы отката (Undo/Rollback)
/// Сохраняет копии файлов ДО каждого изменения, позволяет откатить
class FileSnapshotManager {
    static let shared = FileSnapshotManager()
    
    private let fileManager = FileManager.default
    private let snapshotsBasePath: String
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let snapshotsDir = home.appendingPathComponent(".mycoder/snapshots")
        try? FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        self.snapshotsBasePath = snapshotsDir.path
    }
    
    /// Сохранить снимок файла перед изменением
    /// - Returns: ID снимка для последующего восстановления
    @discardableResult
    func snapshotFile(at path: String, operation: String, sessionId: String) throws -> String {
        let snapshotId = "\(sessionId)_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
        let snapshotDir = "\(snapshotsBasePath)/\(snapshotId)"
        
        try fileManager.createDirectory(atPath: snapshotDir, withIntermediateDirectories: true)
        
        if fileManager.fileExists(atPath: path) {
            let content = try Data(contentsOf: URL(fileURLWithPath: path))
            try content.write(to: URL(fileURLWithPath: "\(snapshotDir)/original"))
            
            // Сохраняем метаданные
            let meta: [String: Any] = [
                "filePath": path,
                "operation": operation,
                "timestamp": Date().timeIntervalSince1970,
                "sessionId": sessionId,
                "fileSize": content.count
            ]
            let metaData = try JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted)
            try metaData.write(to: URL(fileURLWithPath: "\(snapshotDir)/metadata.json"))
        }
        
        return snapshotId
    }
    
    /// Восстановить файл из снимка
    func restoreFromSnapshot(snapshotId: String) throws {
        let snapshotDir = "\(snapshotsBasePath)/\(snapshotId)"
        let originalPath = "\(snapshotDir)/original"
        let metaPath = "\(snapshotDir)/metadata.json"
        
        guard fileManager.fileExists(atPath: originalPath),
              fileManager.fileExists(atPath: metaPath) else {
            throw SnapshotError.snapshotNotFound
        }
        
        // Читаем метаданные
        let metaData = try Data(contentsOf: URL(fileURLWithPath: metaPath))
        guard let meta = try JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let filePath = meta["filePath"] as? String else {
            throw SnapshotError.invalidMetadata
        }
        
        // Восстанавливаем файл
        let originalContent = try Data(contentsOf: URL(fileURLWithPath: originalPath))
        try originalContent.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }
    
    /// Удалить снимок (после успешного commit или по истечении срока)
    func deleteSnapshot(snapshotId: String) {
        let snapshotDir = "\(snapshotsBasePath)/\(snapshotId)"
        try? fileManager.removeItem(atPath: snapshotDir)
    }
    
    /// Очистить все снимки старше N дней
    func cleanOldSnapshots(maxAgeDays: Int = 7) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: snapshotsBasePath) else { return }
        
        let cutoff = Date().addingTimeInterval(-TimeInterval(maxAgeDays * 86400))
        
        for item in contents {
            let itemPath = "\(snapshotsBasePath)/\(item)"
            guard let attrs = try? fileManager.attributesOfItem(atPath: itemPath),
                  let modDate = attrs[.modificationDate] as? Date,
                  modDate < cutoff else { continue }
            try? fileManager.removeItem(atPath: itemPath)
        }
    }
    
    /// Получить размер всех снимков
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
    
    /// Получить список всех снимков с метаданными
    func listSnapshots(sessionId: String? = nil) -> [[String: Any]] {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: snapshotsBasePath) else { return [] }
        
        var snapshots: [[String: Any]] = []
        for item in contents {
            let metaPath = "\(snapshotsBasePath)/\(item)/metadata.json"
            guard let metaData = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                  let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] else { continue }
            
            if let sessionId, meta["sessionId"] as? String != sessionId { continue }
            
            var entry = meta
            entry["snapshotId"] = item
            snapshots.append(entry)
        }
        return snapshots.sorted { ($0["timestamp"] as? Double ?? 0) > ($1["timestamp"] as? Double ?? 0) }
    }
}

/// Система Undo/Redo для операций с файлами
class UndoRedoManager {
    static let shared = UndoRedoManager()
    
    private let db = DatabaseManager.shared
    private let snapshotManager = FileSnapshotManager.shared
    
    /// Экранировать строку для безопасной интерполяции в SQL
    private func sqlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
    
    /// Выполнить операцию с автоматическим snapshot + запись в undo stack
    func executeWithUndo(
        operation: String,
        filePath: String,
        sessionId: String,
        execute: () throws -> Void
    ) throws {
        // 1. Сохраняем snapshot ДО изменения
        let snapshotId = try snapshotManager.snapshotFile(
            at: filePath,
            operation: operation,
            sessionId: sessionId
        )
        
        // 2. Выполняем операцию
        do {
            try execute()
        } catch {
            // Если операция провалилась — удаляем orphan snapshot
            snapshotManager.deleteSnapshot(snapshotId: snapshotId)
            throw error
        }
        
        // 3. Записываем в undo stack
        let undoId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)
        
        try db.exec("""
            INSERT OR REPLACE INTO undo_stack (id, session_id, action_type, target_path, snapshot_id, created_at, can_undo)
            VALUES ('\(sqlEscape(undoId))', '\(sqlEscape(sessionId))', '\(sqlEscape(operation))', '\(sqlEscape(filePath))', '\(sqlEscape(snapshotId))', \(now), 1)
        """)
    }
    
    /// Откатить последнюю операцию для сессии
    func undo(sessionId: String) throws -> Bool {
        // Ищем последнюю undo-запись для сессии
        struct UndoItem {
            let undoId: String
            let snapshotId: String
            let filePath: String
        }
        
        guard let item: UndoItem = try db.query("""
            SELECT id, snapshot_id, target_path FROM undo_stack
            WHERE session_id = '\(sqlEscape(sessionId))' AND can_undo = 1
            ORDER BY created_at DESC LIMIT 1
        """).compactMap({ row in
            guard row.count >= 3,
                  let undoId = row[0] as? String,
                  let snapshotId = row[1] as? String,
                  let filePath = row[2] as? String else { return nil }
            return UndoItem(undoId: undoId, snapshotId: snapshotId, filePath: filePath)
        }).first else { return false }
        
        // Восстанавливаем из snapshot
        try snapshotManager.restoreFromSnapshot(snapshotId: item.snapshotId)
        
        // Помечаем как отменённое (soft delete)
        try db.exec("UPDATE undo_stack SET can_undo = 0 WHERE id = '\(sqlEscape(item.undoId))'")
        
        return true
    }
    
    /// Получить историю изменений для сессии
    func history(sessionId: String) -> [[String: Any]] {
        return snapshotManager.listSnapshots(sessionId: sessionId)
    }
    
    /// Очистить старые снимки (вызывается раз в день)
    func cleanUp() {
        snapshotManager.cleanOldSnapshots(maxAgeDays: 7)
    }
}

enum SnapshotError: Error, LocalizedError {
    case snapshotNotFound
    case invalidMetadata
    
    var errorDescription: String? {
        switch self {
        case .snapshotNotFound: return "Snapshot not found on disk"
        case .invalidMetadata: return "Snapshot metadata is corrupted"
        }
    }
}
