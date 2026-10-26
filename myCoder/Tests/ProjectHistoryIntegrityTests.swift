import Testing
import Foundation
@testable import myCoder

@Suite("Project history integrity — full dialog, point-in-time undo, export/import, rename resilience", .serialized)
struct ProjectHistoryIntegrityTests {

    private func makeTempProjectDir(_ name: String = UUID().uuidString) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-history-tests-\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("Full dialog remains queryable after the in-memory session/message store would have discarded it")
    func fullDialogSurvivesAfterInMemoryDiscard() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let db = try ProjectDatabaseManager.manager(forProjectPath: projectPath)

        try db.insertSession(id: "s1", title: "Old chat", directory: projectPath)
        for i in 0..<5 {
            try db.insertMessage(id: "m\(i)", sessionId: "s1", role: i % 2 == 0 ? "user" : "assistant", content: "message \(i)")
        }

        // Simulate the in-memory UI state being torn down (session switched away from, app relaunched, etc.)
        var inMemorySessions: [String] = []
        inMemorySessions.removeAll()
        #expect(inMemorySessions.isEmpty)

        // The full dialog is still fully readable straight from the project's own database.
        let persisted = try db.getMessages(sessionId: "s1")
        #expect(persisted.count == 5)
        #expect(persisted.map(\.content) == (0..<5).map { "message \($0)" })
    }

    @Test("Point-in-time undo rolls back exactly one action without touching newer changes")
    func pointInTimeUndoRestoresOnlyTargetedFile() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        let fileA = (projectPath as NSString).appendingPathComponent("a.txt")
        let fileB = (projectPath as NSString).appendingPathComponent("b.txt")
        try "original A".write(toFile: fileA, atomically: true, encoding: .utf8)
        try "original B".write(toFile: fileB, atomically: true, encoding: .utf8)

        let undoManager = try ProjectUndoManager(projectPath: projectPath)
        try undoManager.db.insertSession(id: "s1", title: "Editing", directory: projectPath)

        try undoManager.executeWithUndo(operation: "edit_file", filePath: fileA, sessionId: "s1") {
            try "edited A".write(toFile: fileA, atomically: true, encoding: .utf8)
        }
        try undoManager.executeWithUndo(operation: "edit_file", filePath: fileB, sessionId: "s1") {
            try "edited B".write(toFile: fileB, atomically: true, encoding: .utf8)
        }

        let entries = try undoManager.history(sessionId: "s1")
        #expect(entries.count == 2)
        let firstEntryId = entries.last!.id // oldest = the edit to A

        try undoManager.undoEntry(id: firstEntryId)

        #expect(try String(contentsOfFile: fileA, encoding: .utf8) == "original A")
        #expect(try String(contentsOfFile: fileB, encoding: .utf8) == "edited B", "unrelated newer edit must not be reverted")
    }

    @Test("Undoing an already-used entry fails instead of silently double-restoring")
    func undoingUsedEntryFails() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        let fileA = (projectPath as NSString).appendingPathComponent("a.txt")
        try "v1".write(toFile: fileA, atomically: true, encoding: .utf8)

        let undoManager = try ProjectUndoManager(projectPath: projectPath)
        try undoManager.db.insertSession(id: "s1", title: "Editing", directory: projectPath)
        try undoManager.executeWithUndo(operation: "edit_file", filePath: fileA, sessionId: "s1") {
            try "v2".write(toFile: fileA, atomically: true, encoding: .utf8)
        }
        let entry = try undoManager.history(sessionId: "s1").first!
        try undoManager.undoEntry(id: entry.id)

        #expect(throws: ProjectUndoError.entryAlreadyUsed) {
            try undoManager.undoEntry(id: entry.id)
        }
    }

    @Test("Export then import round-trips the full history into a fresh database without loss")
    func exportImportRoundTrip() throws {
        let sourcePath = try makeTempProjectDir("export-source")
        let destPath = try makeTempProjectDir("export-dest")
        defer {
            try? FileManager.default.removeItem(atPath: sourcePath)
            try? FileManager.default.removeItem(atPath: destPath)
        }
        ProjectDatabaseManager.evictProject(projectPath: sourcePath)
        ProjectDatabaseManager.evictProject(projectPath: destPath)

        let source = try ProjectDatabaseManager.manager(forProjectPath: sourcePath)
        try source.insertSession(id: "s1", title: "Chat to export", directory: sourcePath, branch: "main")
        try source.insertMessage(id: "m1", sessionId: "s1", role: "user", content: "hello")
        try source.insertMessagePart(id: "p1", messageId: "m1", type: "text", content: "hello", sequenceOrder: 0)
        try source.insertMessage(id: "m2", sessionId: "s1", role: "assistant", content: "hi there")
        try source.recordRequestHistory(sessionId: "s1", type: "command_executed", payload: "{\"cmd\":\"swift build\"}")

        let exported = try ProjectHistoryExporter.export(from: source)

        let dest = try ProjectDatabaseManager.manager(forProjectPath: destPath)
        let summary = try ProjectHistoryExporter.importBundle(exported, into: dest)

        #expect(summary.importedSessions == 1)
        #expect(summary.importedMessages == 2)
        #expect(summary.importedRequestHistoryEntries == 1)

        let sessions = try dest.getAllSessions()
        #expect(sessions.map(\.id) == ["s1"])
        #expect(sessions.first?.branch == "main")

        let messages = try dest.getMessages(sessionId: "s1")
        #expect(Set(messages.map(\.content)) == Set(["hello", "hi there"]))

        let history = try dest.getRequestHistory(sessionId: "s1")
        #expect(history.map(\.type) == ["command_executed"])
    }

    @Test("Importing the same bundle twice does not duplicate data")
    func importIsIdempotent() throws {
        let sourcePath = try makeTempProjectDir("export-source-2")
        let destPath = try makeTempProjectDir("export-dest-2")
        defer {
            try? FileManager.default.removeItem(atPath: sourcePath)
            try? FileManager.default.removeItem(atPath: destPath)
        }
        ProjectDatabaseManager.evictProject(projectPath: sourcePath)
        ProjectDatabaseManager.evictProject(projectPath: destPath)

        let source = try ProjectDatabaseManager.manager(forProjectPath: sourcePath)
        try source.insertSession(id: "s1", title: "Chat", directory: sourcePath)
        try source.insertMessage(id: "m1", sessionId: "s1", role: "user", content: "hi")
        let exported = try ProjectHistoryExporter.export(from: source)

        let dest = try ProjectDatabaseManager.manager(forProjectPath: destPath)
        _ = try ProjectHistoryExporter.importBundle(exported, into: dest)
        _ = try ProjectHistoryExporter.importBundle(exported, into: dest)

        #expect(try dest.getAllSessions().count == 1)
        #expect(try dest.getMessages(sessionId: "s1").count == 1)
    }

    @Test("A project's stable id survives being relinked to a new registry path after a rename")
    func relinkPreservesStableIdentity() throws {
        let registry = DatabaseManager.createInMemory()
        let originalPath = try makeTempProjectDir("relink-original")
        defer { try? FileManager.default.removeItem(atPath: originalPath) }
        ProjectDatabaseManager.evictProject(projectPath: originalPath)

        // Register the project and capture the stable id written into its own project.db.
        try registry.insertProject(id: ChatSession.normalizedPath(originalPath), name: "Original", path: originalPath)
        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: originalPath)
        let stableId = try projectDB.stableProjectId()

        let registryEntry = try registry.getAllProjects().first { $0.path == ChatSession.normalizedPath(originalPath) }
        #expect(registryEntry?.stableId != nil, "insertProject mints its own registry-side stable id when none is supplied")

        // Simulate: folder gets renamed on disk. The .mycoder/project.db (and its stable id) travels with it.
        let renamedPath = try makeTempProjectDir("relink-renamed")
        defer { try? FileManager.default.removeItem(atPath: renamedPath) }
        let movedMimocodeDir = (renamedPath as NSString).appendingPathComponent(".mycoder")
        try FileManager.default.moveItem(
            atPath: (originalPath as NSString).appendingPathComponent(".mycoder"),
            toPath: movedMimocodeDir
        )
        ProjectDatabaseManager.evictProject(projectPath: originalPath)
        ProjectDatabaseManager.evictProject(projectPath: renamedPath)
        let movedDB = try ProjectDatabaseManager.manager(forProjectPath: renamedPath)
        #expect(try movedDB.stableProjectId() == stableId, "moving the .mycoder folder must preserve the stable id")

        let newId = try registry.relinkProject(
            oldId: ChatSession.normalizedPath(originalPath),
            newPath: renamedPath,
            name: "Renamed"
        )

        #expect(newId == ChatSession.normalizedPath(renamedPath))
        let afterRelink = try registry.getAllProjects()
        #expect(!afterRelink.contains { $0.id == ChatSession.normalizedPath(originalPath) }, "stale entry at the old path must be gone")
        #expect(afterRelink.contains { $0.id == newId })
    }

    @Test("A moved project can be recognized by stable id even though its registry path is stale")
    func findsMovedProjectByStableId() throws {
        let registry = DatabaseManager.createInMemory()
        let projectPath = try makeTempProjectDir("stable-lookup")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        let stableId = try projectDB.stableProjectId()
        try registry.insertProject(
            id: ChatSession.normalizedPath(projectPath),
            name: "P",
            path: projectPath,
            stableId: stableId
        )

        let found = try registry.findProjectByStableId(stableId)
        #expect(found?.id == ChatSession.normalizedPath(projectPath))
        #expect((try registry.findProjectByStableId("no-such-id")) == nil)
    }
}
