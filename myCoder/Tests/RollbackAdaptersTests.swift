import Testing
import Foundation
@testable import myCoder

/// Адаптеры реального окружения отката: загрузка undo-записей и корзина.
@Suite("Откат — адаптеры окружения")
struct RollbackAdaptersTests {

    @Test("Проектная запись → RollbackUndoEntryRef")
    func projectRecordMapped() {
        let record = ProjectUndoEntryRecord(
            id: "u1", sessionId: "s1", actionType: "edit_file",
            targetPath: "src/a.swift", snapshotId: "snap1",
            createdAt: Date(timeIntervalSince1970: 1000), canUndo: true)
        let ref = RollbackUndoLoader.ref(from: record)
        #expect(ref?.id == "u1")
        #expect(ref?.path == "src/a.swift")
        #expect(ref?.snapshotID == "snap1")
        #expect(ref?.canUndo == true)
        #expect(ref?.createdAt == 1000)
    }

    @Test("Проектная запись без пути → nil")
    func projectRecordWithoutPathNil() {
        let record = ProjectUndoEntryRecord(
            id: "u1", sessionId: "s1", actionType: "edit_file",
            targetPath: nil, snapshotId: "snap1",
            createdAt: Date(), canUndo: true)
        #expect(RollbackUndoLoader.ref(from: record) == nil)
    }

    @Test("Глобальная строка снапшота → RollbackUndoEntryRef")
    func globalRowMapped() {
        let row: [String: Any] = [
            "snapshotId": "s1_123_abcd",
            "filePath": "/tmp/a.swift",
            "sessionId": "ses1",
            "operation": "write_file",
            "timestamp": 2_000_000.0,
        ]
        let ref = RollbackUndoLoader.ref(globalRow: row, sessionID: "ses1")
        #expect(ref?.snapshotID == "s1_123_abcd")
        #expect(ref?.path == "/tmp/a.swift")
        #expect(ref?.actionType == "write_file")
        #expect(ref?.createdAt == 2_000_000.0)
        // Чужая сессия отфильтровывается.
        #expect(RollbackUndoLoader.ref(globalRow: row, sessionID: "other") == nil)
    }

    @Test("Корзина копирует файл перед восстановлением")
    func trashStoreCopiesFile() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("rollback-trash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let file = home.appendingPathComponent("a.swift")
        try "let x = 1".write(to: file, atomically: true, encoding: .utf8)

        let store = RollbackTrashStore(homeDirectory: home)
        let saved = try store.storeCopy(ofFileAt: file.path, scope: "rollback")
        #expect(saved != nil)
        #expect(FileManager.default.fileExists(atPath: saved!))
        #expect(try String(contentsOfFile: saved!, encoding: .utf8) == "let x = 1")
        // Оригинал не тронут.
        #expect(try String(contentsOfFile: file.path, encoding: .utf8) == "let x = 1")
    }

    @Test("Корзина пропускает несуществующий файл")
    func trashStoreSkipsMissingFile() throws {
        let store = RollbackTrashStore(homeDirectory: FileManager.default.temporaryDirectory)
        #expect(try store.storeCopy(ofFileAt: "/tmp/no-such-file-\(UUID().uuidString)", scope: "rollback") == nil)
    }
}
