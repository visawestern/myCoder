import Foundation

enum ProjectUndoError: Error, LocalizedError, Equatable {
    case entryNotFound
    case entryAlreadyUsed
    case missingSnapshot

    var errorDescription: String? {
        switch self {
        case .entryNotFound: return "Undo entry not found"
        case .entryAlreadyUsed: return "This action has already been undone"
        case .missingSnapshot: return "No file snapshot recorded for this action"
        }
    }
}

/// Per-project replacement for the legacy global `UndoRedoManager`. Every
/// operation's snapshot and undo-stack entry are scoped to the project's own
/// database and `.mycoder/snapshots/` folder, and — unlike the legacy
/// "undo the single most recent action" API — any individual entry can be
/// rolled back independently of the others around it.
final class ProjectUndoManager {
    let db: ProjectDatabaseManager
    let snapshotManager: ProjectSnapshotManager

    init(projectPath: String) throws {
        self.db = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        self.snapshotManager = try ProjectSnapshotManager(projectPath: projectPath)
    }

    /// Runs `execute`, having first captured a snapshot of `filePath` so the
    /// change can be rolled back later. If `execute` throws, the orphaned
    /// snapshot is discarded and no undo entry is recorded.
    func executeWithUndo(
        operation: String,
        filePath: String,
        sessionId: String,
        execute: () throws -> Void
    ) throws {
        let snapshotId = try snapshotManager.snapshotFile(at: filePath, operation: operation, sessionId: sessionId)
        do {
            try execute()
        } catch {
            snapshotManager.deleteSnapshot(snapshotId: snapshotId)
            throw error
        }
        try db.insertUndoEntry(
            id: UUID().uuidString,
            sessionId: sessionId,
            actionType: operation,
            targetPath: filePath,
            snapshotId: snapshotId
        )
    }

    /// Rolls back the most recent still-usable action for `sessionId`
    /// (parity with the legacy "Undo Last File Change" menu command).
    @discardableResult
    func undoMostRecent(sessionId: String) throws -> Bool {
        guard let entry = try db.getUndoStack(sessionId: sessionId, onlyUsable: true).first else {
            return false
        }
        try undoEntry(id: entry.id)
        return true
    }

    /// Rolls back exactly one specific action, regardless of how many newer
    /// actions have happened since — this is the point-in-time rollback the
    /// legacy "undo everything" stack could not do.
    func undoEntry(id: String) throws {
        guard let entry = try db.getUndoEntry(id: id) else {
            throw ProjectUndoError.entryNotFound
        }
        guard entry.canUndo else {
            throw ProjectUndoError.entryAlreadyUsed
        }
        guard let snapshotId = entry.snapshotId else {
            throw ProjectUndoError.missingSnapshot
        }
        try snapshotManager.restoreFromSnapshot(snapshotId: snapshotId)
        try db.markUndoEntryUsed(id: id)
    }

    func history(sessionId: String) throws -> [ProjectUndoEntryRecord] {
        try db.getUndoStack(sessionId: sessionId)
    }
}
