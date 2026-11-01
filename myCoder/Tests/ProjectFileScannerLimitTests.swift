import Testing
import Foundation
@testable import myCoder

/// Сканер проекта не должен превращаться в бесконечную операцию:
/// лимит количества записей срезает гигантские репозитории
/// (user report 2026-10-30: «собирает контекст уже час»).
@Suite("ProjectFileScanner лимит индекса")
struct ProjectFileScannerLimitTests {

    @Test("Сканер уважает maxRecords")
    func scanRespectsMaxRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 50 маленьких файлов.
        for i in 0..<50 {
            let file = root.appendingPathComponent("f\(i).swift")
            try "let x\(i) = \(i)".write(to: file, atomically: true, encoding: .utf8)
        }

        let limited = ProjectFileScanner.scan(root: root.path, maxRecords: 10)
        #expect(limited.count == 10)

        let full = ProjectFileScanner.scan(root: root.path)
        #expect(full.count == 50)
    }

    @Test("Дефолтный лимит существует и конечен")
    func defaultLimitIsFinite() {
        #expect(ProjectFileIndexLogic.defaultMaxIndexRecords > 0)
        #expect(ProjectFileIndexLogic.defaultMaxIndexRecords < 1_000_000)
    }

    @Test("Сканер уважает maxReadBytes (байтовый бюджет)")
    func scanRespectsMaxReadBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-bytes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 3 файла по 100 байт каждый.
        let payload = String(repeating: "x", count: 100)
        for i in 0..<3 {
            let file = root.appendingPathComponent("b\(i).swift")
            try payload.write(to: file, atomically: true, encoding: .utf8)
        }

        // Бюджет 150 байт: влезает ровно один файл (100 Б), второй чтение
        // уже превышает бюджет → скан останавливается.
        let single = ProjectFileScanner.scan(root: root.path, maxReadBytes: 150)
        #expect(single.count == 1)

        let full = ProjectFileScanner.scan(root: root.path)
        #expect(full.count == 3)
    }

    @Test("Дефолтный байтовый бюджет существует и конечен")
    func defaultReadBudgetIsFinite() {
        #expect(ProjectFileIndexLogic.defaultMaxScanBytes > 0)
        #expect(ProjectFileIndexLogic.defaultMaxScanBytes < 10 * 1024 * 1024 * 1024)
    }

    @Test("Усечение текста не теряет файл, если разрезало многобайтовый символ")
    func truncationSplitsMultibyteCharacter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-utf8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Ровно на границе кэпа (96 КБ) начинается двухбайтовая «я»:
        // префикс обрезает её посередине. Строгий UTF-8 decode вернул бы nil,
        // и файл потерял бы весь поисковый текст.
        let prefix = String(repeating: "a", count: ProjectFileIndexLogic.defaultIndexSearchableTextMaxBytes - 1)
        try (prefix + "я хвост").write(
            to: root.appendingPathComponent("Cyrillic.swift"),
            atomically: true,
            encoding: .utf8
        )

        let rec = try #require(
            ProjectFileScanner.scan(root: root.path).first { $0.path == "Cyrillic.swift" }
        )
        #expect(rec.searchableText != nil)
        #expect(rec.searchableText?.hasPrefix("aaa") == true)
    }

    @Test("Сканер хранит урезанный текст (не полный файл)")
    func scanStoresTruncatedSearchableText() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-trunc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 200 КБ текста — больше кэпа хранимого текста (96 КБ).
        let big = String(repeating: "let line = 1\n", count: 12_000) // ~156 КБ
        try big.write(to: root.appendingPathComponent("Big.swift"), atomically: true, encoding: .utf8)

        let rec = try #require(
            ProjectFileScanner.scan(root: root.path).first { $0.path == "Big.swift" }
        )
        let stored = rec.searchableText ?? ""
        #expect(!stored.isEmpty)
        #expect(stored.utf8.count <= ProjectFileIndexLogic.defaultIndexSearchableTextMaxBytes)
        #expect(stored.utf8.count < big.utf8.count)
    }
}
