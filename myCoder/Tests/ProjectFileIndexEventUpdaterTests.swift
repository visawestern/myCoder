import Testing
import Foundation
@testable import myCoder

/// Событийный апдейтер индекса: FSEvents-событие обновляет только
/// затронутые файлы/папки, а не пересканирует весь проект.
@Suite("ProjectFileIndexEventUpdater — событийная переиндексация")
struct ProjectFileIndexEventUpdaterTests {

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("evidx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "import Foundation\nfinal class A {}\n"
            .write(to: root.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        let src = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "let x = 1\n"
            .write(to: src.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)
        return root
    }

    /// Baseline через реальный скан (как это делает PointContextIndexLogic).
    private func baseline(_ root: URL) -> [FileIndexRecord] {
        PointContextIndexLogic.records(projectPath: root.path)
    }

    private func record(byPath path: String, in records: [FileIndexRecord]) -> FileIndexRecord? {
        records.first { $0.path == path }
    }

    @Test("Изменённый файл пере-индексируется (новый хэш), остальные не тронуты")
    func changedFileIsReindexed() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let stored = baseline(root)
        let before = try #require(record(byPath: "A.swift", in: stored))

        try "import Foundation\nfinal class AB {}\n"
            .write(to: root.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [root.appendingPathComponent("A.swift").path],
            stored: stored,
            projectPath: root.path
        )
        let after = try #require(record(byPath: "A.swift", in: updated))
        #expect(after.hash != before.hash)
        #expect(after.searchableText?.contains("AB") == true)
        // Соседний файл не перечитывался и не менялся.
        #expect(record(byPath: "Sources/B.swift", in: updated)?.hash
                == record(byPath: "Sources/B.swift", in: stored)?.hash)
    }

    @Test("Удалённый файл убирается из индекса")
    func deletedFileIsRemoved() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let stored = baseline(root)
        let path = root.appendingPathComponent("A.swift").path
        try FileManager.default.removeItem(atPath: path)

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [path],
            stored: stored,
            projectPath: root.path
        )
        #expect(record(byPath: "A.swift", in: updated) == nil)
        #expect(record(byPath: "Sources/B.swift", in: updated) != nil)
    }

    @Test("Новый файл в изменённой папке добавляется; сосед не тронут")
    func newFileInChangedDirectoryIsAdded() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let stored = baseline(root)
        let src = root.appendingPathComponent("Sources", isDirectory: true)
        try "let y = 2\n".write(
            to: src.appendingPathComponent("C.swift"),
            atomically: true,
            encoding: .utf8
        )

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [src.path],
            stored: stored,
            projectPath: root.path
        )
        #expect(record(byPath: "Sources/C.swift", in: updated) != nil)
        #expect(record(byPath: "Sources/B.swift", in: updated)?.hash
                == record(byPath: "Sources/B.swift", in: stored)?.hash)
    }

    @Test("Удаление папки убирает всё поддерево")
    func deletedDirectoryRemovesSubtree() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let stored = baseline(root)
        let src = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.removeItem(at: src)

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [src.path],
            stored: stored,
            projectPath: root.path
        )
        #expect(record(byPath: "Sources/B.swift", in: updated) == nil)
        #expect(record(byPath: "A.swift", in: updated) != nil)
    }

    @Test("Исключённые пути не трогают индекс")
    func excludedPathsAreIgnored() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let stored = baseline(root)
        let nm = root.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nm, withIntermediateDirectories: true)
        try "{}".write(to: nm.appendingPathComponent("pkg.json"), atomically: true, encoding: .utf8)

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [nm.path, root.appendingPathComponent("node_modules/pkg.json").path],
            stored: stored,
            projectPath: root.path
        )
        #expect(record(byPath: "node_modules/pkg.json", in: updated) == nil)
        #expect(updated.map(\.path) == stored.map(\.path))
    }

    @Test("Секретный файл (.env) не попадает в индекс и убирается")
    func secretFileIsNeverIndexed() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let secret = root.appendingPathComponent(".env")
        try "API_KEY=secret\n".write(to: secret, atomically: true, encoding: .utf8)

        // Имитируем «протёкшую» запись в хранилище.
        let fake = FileIndexRecord(
            path: ".env",
            hash: "h",
            size: 20,
            lastModified: 1_700_000_000,
            language: "text",
            searchableText: "API_KEY=secret"
        )
        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [secret.path],
            stored: [fake],
            projectPath: root.path
        )
        #expect(record(byPath: ".env", in: updated) == nil)
    }

    @Test("Пути вне проекта игнорируются")
    func outsidePathsAreIgnored() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let stored = baseline(root)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).swift")
        try "let z = 3".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [outside.path],
            stored: stored,
            projectPath: root.path
        )
        #expect(updated == stored)
    }

    @Test("Собственная папка данных (.mycoder) игнорируется")
    func appDataDirIsIgnored() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let stored = baseline(root)
        let dataDir = root.appendingPathComponent(".mycoder", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let indexPath = dataDir.appendingPathComponent("file_index.json")
        try "{\"projectPath\":\"x\",\"records\":[]}"
            .write(to: indexPath, atomically: true, encoding: .utf8)

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [indexPath.path],
            stored: stored,
            projectPath: root.path
        )
        #expect(updated == stored)
    }

    @Test("Обрезанный батч не удаляет необработанные записи директории")
    func truncatedDirectoryBatchKeepsUnvisitedRecords() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let src = root.appendingPathComponent("Sources", isDirectory: true)
        for i in 0..<6 {
            try "let v\(i) = \(i)\n".write(
                to: src.appendingPathComponent("Extra\(i).swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        let stored = baseline(root)
        #expect(stored.count == 8)

        var options = ProjectFileIndexEventUpdater.Options()
        options.maxFilesPerBatch = 2

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [src.path],
            stored: stored,
            projectPath: root.path,
            options: options
        )
        // Батч обработал только часть папки — остальные записи живые и
        // обязаны остаться в индексе.
        #expect(updated.count == stored.count)
        for record in stored {
            #expect(updated.contains { $0.path == record.path })
        }
    }

    @Test("Событие по корню проекта обновляет файл, даже если путь содержит build")
    func projectRootEventWorksUnderExcludedComponent() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("build-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let file = root.appendingPathComponent("A.swift")
        try "let a = 1\n".write(to: file, atomically: true, encoding: .utf8)
        let stored = baseline(root)
        let before = try #require(record(byPath: "A.swift", in: stored))

        try "let a = 2\n".write(to: file, atomically: true, encoding: .utf8)
        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [root.path],
            stored: stored,
            projectPath: root.path
        )
        let after = try #require(record(byPath: "A.swift", in: updated))
        #expect(after.hash != before.hash)
    }

    @Test("Событие по корню убирает устаревшую запись из исключённой папки")
    func rootEventRemovesStaleExcludedRecord() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let nm = root.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nm, withIntermediateDirectories: true)
        try "{}".write(to: nm.appendingPathComponent("pkg.json"), atomically: true, encoding: .utf8)

        let stale = FileIndexRecord(
            path: "node_modules/pkg.json",
            hash: "stale",
            size: 2,
            lastModified: 1_700_000_000,
            language: "json",
            searchableText: "{}"
        )
        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [root.path],
            stored: [stale],
            projectPath: root.path
        )
        #expect(record(byPath: "node_modules/pkg.json", in: updated) == nil)
    }

    @Test("Событие по корню убирает удалённый файл")
    func rootEventRemovesDeletedFile() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let stored = baseline(root)
        let deleted = root.appendingPathComponent("A.swift")
        try FileManager.default.removeItem(at: deleted)

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [root.path],
            stored: stored,
            projectPath: root.path
        )
        #expect(record(byPath: "A.swift", in: updated) == nil)
        #expect(record(byPath: "Sources/B.swift", in: updated) != nil)
    }

    @Test("События не растят индекс выше maxRecords")
    func eventBatchRespectsRecordCap() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let stored = baseline(root)
        var options = ProjectFileIndexEventUpdater.Options()
        options.maxRecords = stored.count

        let added = root.appendingPathComponent("New.swift")
        try "let n = 1\n".write(to: added, atomically: true, encoding: .utf8)

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [added.path],
            stored: stored,
            projectPath: root.path,
            options: options
        )
        #expect(updated.count == stored.count)
        #expect(record(byPath: "New.swift", in: updated) == nil)
    }

    @Test("Файл больше лимита не индексируется и убирается")
    func oversizedFileIsNotIndexed() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let big = root.appendingPathComponent("big.bin")
        let data = Data(repeating: 0x41, count: 2_000_000)
        try data.write(to: big)

        let fake = FileIndexRecord(
            path: "big.bin",
            hash: "h",
            size: data.count,
            lastModified: 1_700_000_000,
            language: "bin",
            searchableText: nil
        )
        var options = ProjectFileIndexEventUpdater.Options()
        options.maxFileSize = 1_000_000

        let updated = ProjectFileIndexEventUpdater.apply(
            changedPaths: [big.path],
            stored: [fake],
            projectPath: root.path,
            options: options
        )
        #expect(record(byPath: "big.bin", in: updated) == nil)
    }
}
