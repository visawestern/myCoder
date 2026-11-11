import Testing
import Foundation
@testable import myCoder

/// Безопасное удаление данных проекта: отказ для пустых/небезопасных
/// путей и реальное удаление временной папки `.mycoder` внутри проекта.
@MainActor
@Suite("Удаление данных проекта (ProjectDeletionExecutor)")
struct ProjectDeletionExecutorTests {

    @Test("Пустой путь отклоняется")
    func emptyPathFailsSafely() {
        let outcome = ProjectDeletionExecutor.execute(projectPath: "")
        guard case .failed = outcome else {
            Issue.record("пустой путь должен завершиться failure")
            return
        }
    }

    @Test("Удаление успешно стирает .mycoder проекта")
    func deletesProjectData() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("proj-del-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let dataDir = ProjectDatabaseLocator.projectMimoDir(projectPath: root.path)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let db = dataDir.appendingPathComponent("project.db")
        try "data".write(to: db, atomically: true, encoding: .utf8)

        let outcome = ProjectDeletionExecutor.execute(projectPath: root.path)
        #expect(outcome == .completed)
        #expect(!FileManager.default.fileExists(atPath: dataDir.path))
        #expect(FileManager.default.fileExists(atPath: root.path), "сам проект остаётся")
    }

    @Test("deleteProjectData возвращает true при успехе")
    func deleteProjectDataBool() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("proj-del2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let dataDir = ProjectDatabaseLocator.projectMimoDir(projectPath: root.path)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try "x".write(to: dataDir.appendingPathComponent("f"), atomically: true, encoding: .utf8)

        #expect(ProjectDeletionExecutor.deleteProjectData(projectPath: root.path))
        #expect(!ProjectDeletionExecutor.deleteProjectData(projectPath: ""))
    }
}
