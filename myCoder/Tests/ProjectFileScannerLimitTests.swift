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
}
