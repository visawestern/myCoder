import Testing
import Foundation
@testable import myCoder

/// Storage audit log (plan Раздел 8 п.46): every registry operation
/// (create/archive/restore/delete/relink/reset) is appended to a timestamped
/// log so future "something appeared on its own" reports can be diagnosed.
@Suite("Storage audit log (plan Раздел 8 п.46)")
struct StorageAuditLogTests {

    @Test func appendCreatesLogInHomeDir() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try StorageAuditLog.append(action: "create", detail: "proj", homeDirectory: home)
        let url = StorageAuditLog.logURL(homeDirectory: home)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("create"))
        #expect(content.contains("proj"))
    }

    @Test func appendAddsNewLines() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try StorageAuditLog.append(action: "archive", detail: "a", homeDirectory: home)
        try StorageAuditLog.append(action: "delete", detail: "b", homeDirectory: home)
        let content = try String(contentsOf: StorageAuditLog.logURL(homeDirectory: home), encoding: .utf8)
        let lines = content.split(separator: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 2)
    }

    @Test func linesAreTimestamped() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try StorageAuditLog.append(action: "reset", detail: "full", homeDirectory: home)
        let content = try String(contentsOf: StorageAuditLog.logURL(homeDirectory: home), encoding: .utf8)
        // ISO8601 timestamp prefix: 2026-08-01T14:00:00Z
        #expect(content.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"#, options: .regularExpression) != nil)
    }

    @Test func logIsAppendOnlyNeverRewrites() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try StorageAuditLog.append(action: "one", detail: "1", homeDirectory: home)
        try StorageAuditLog.append(action: "two", detail: "2", homeDirectory: home)
        try StorageAuditLog.append(action: "three", detail: "3", homeDirectory: home)
        let content = try String(contentsOf: StorageAuditLog.logURL(homeDirectory: home), encoding: .utf8)
        // All three must be present in order.
        let one = content.range(of: "one")?.lowerBound
        let two = content.range(of: "two")?.lowerBound
        let three = content.range(of: "three")?.lowerBound
        #expect(one != nil && two != nil && three != nil)
        #expect(one! < two! && two! < three!)
    }

    // MARK: - Helpers

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
