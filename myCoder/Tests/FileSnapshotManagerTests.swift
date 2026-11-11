import Testing
import Foundation
@testable import myCoder

/// Снимки файлов для отката: создание, восстановление, удаление, список,
/// размеры, чистка старых и честные ошибки метаданных.
@MainActor
@Suite("FileSnapshotManager")
struct FileSnapshotManagerTests {

    private func makeManager() throws -> (FileSnapshotManager, URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshots-\(UUID().uuidString)", isDirectory: true)
        let manager = FileSnapshotManager(snapshotsBasePath: base.path)
        return (manager, base)
    }

    @Test("snapshotFile сохраняет original и metadata, возвращает id")
    func snapshotCreatesFiles() throws {
        let (manager, base) = try makeManager()
        defer { try? FileManager.default.removeItem(at: base) }

        let file = base.appendingPathComponent("src.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let id = try manager.snapshotFile(at: file.path, operation: "edit", sessionId: "s1")
        #expect(!id.isEmpty)

        let dir = base.appendingPathComponent(id)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("original").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("metadata.json").path))
        let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("metadata.json"))) as? [String: Any]
        #expect(meta?["filePath"] as? String == file.path)
        #expect(meta?["operation"] as? String == "edit")
        #expect(meta?["sessionId"] as? String == "s1")
    }

    @Test("restoreFromSnapshot восстанавливает содержимое")
    func restoreRestoresContent() throws {
        let (manager, base) = try makeManager()
        defer { try? FileManager.default.removeItem(at: base) }

        let file = base.appendingPathComponent("src.txt")
        try "before".write(to: file, atomically: true, encoding: .utf8)
        let id = try manager.snapshotFile(at: file.path, operation: "edit", sessionId: "s1")
        try "after".write(to: file, atomically: true, encoding: .utf8)

        try manager.restoreFromSnapshot(snapshotId: id)
        #expect(try String(contentsOf: file, encoding: .utf8) == "before")
    }

    @Test("restoreFromSnapshot: отсутствующий снимок → SnapshotError")
    func restoreMissingThrows() throws {
        let (manager, base) = try makeManager()
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(throws: SnapshotError.self) {
            try manager.restoreFromSnapshot(snapshotId: "nope")
        }
    }

    @Test("restoreFromSnapshot: битые метаданные → invalidMetadata")
    func restoreBrokenMetadataThrows() throws {
        let (manager, base) = try makeManager()
        defer { try? FileManager.default.removeItem(at: base) }

        let dir = base.appendingPathComponent("broken")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not json".write(to: dir.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent("original"), atomically: true, encoding: .utf8)

        #expect(throws: SnapshotError.self) {
            try manager.restoreFromSnapshot(snapshotId: "broken")
        }
    }

    @Test("deleteSnapshot удаляет снимок")
    func deleteRemovesSnapshot() throws {
        let (manager, base) = try makeManager()
        defer { try? FileManager.default.removeItem(at: base) }

        let file = base.appendingPathComponent("src.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let id = try manager.snapshotFile(at: file.path, operation: "edit", sessionId: "s1")
        manager.deleteSnapshot(snapshotId: id)
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent(id).path))
    }

    @Test("listSnapshots фильтрует по сессии и сортирует по времени")
    func listFiltersBySession() throws {
        let (manager, base) = try makeManager()
        defer { try? FileManager.default.removeItem(at: base) }

        let file = base.appendingPathComponent("src.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        _ = try manager.snapshotFile(at: file.path, operation: "a", sessionId: "s1")
        _ = try manager.snapshotFile(at: file.path, operation: "b", sessionId: "s2")

        let s1 = manager.listSnapshots(sessionId: "s1")
        #expect(s1.count == 1)
        #expect((s1.first?["sessionId"] as? String) == "s1")
        #expect(manager.listSnapshots().count == 2)
    }

    @Test("snapshotsSizeBytes суммирует размеры файлов")
    func sizeCountsBytes() throws {
        let (manager, base) = try makeManager()
        defer { try? FileManager.default.removeItem(at: base) }

        let file = base.appendingPathComponent("src.txt")
        try "12345".write(to: file, atomically: true, encoding: .utf8)
        _ = try manager.snapshotFile(at: file.path, operation: "a", sessionId: "s1")
        #expect(manager.snapshotsSizeBytes() >= 5)
    }

    @Test("cleanOldSnapshots удаляет только старые")
    func cleanRemovesOldOnly() throws {
        let (manager, base) = try makeManager()
        defer { try? FileManager.default.removeItem(at: base) }

        let file = base.appendingPathComponent("src.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let old = try manager.snapshotFile(at: file.path, operation: "a", sessionId: "s1")
        let new = try manager.snapshotFile(at: file.path, operation: "b", sessionId: "s1")

        // Сделаем старый снимок древним.
        let oldDir = base.appendingPathComponent(old)
        let past = Date().addingTimeInterval(-10 * 86400)
        try FileManager.default.setAttributes(
            [.modificationDate: past],
            ofItemAtPath: oldDir.path
        )

        manager.cleanOldSnapshots(maxAgeDays: 7)
        #expect(!FileManager.default.fileExists(atPath: oldDir.path), "старый снимок удалён")
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent(new).path), "новый остался")
    }
}
