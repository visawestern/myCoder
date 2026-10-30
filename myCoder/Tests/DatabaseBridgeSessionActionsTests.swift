import Testing
import Foundation
@testable import myCoder

@Suite("DatabaseBridge — sidebar session actions (program DB only)", .serialized)
struct DatabaseBridgeSessionActionsTests {

    private func makeTempProjectDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-bridge-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private func programRows(_ projectPath: String, includeArchived: Bool = false) throws -> [SessionRecord] {
        try DatabaseManager.shared.getSessionsByProject(
            projectId: ChatSession.normalizedPath(projectPath),
            includeArchived: includeArchived
        )
    }

    @Test("Rename/delete живут в базе программы и возвращают реальные изменения")
    func renameAndDeleteProjectSession() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let sessionID = "s1-\(UUID().uuidString)"

        let bridge = DatabaseBridge()
        bridge.createSession(id: sessionID, projectId: projectPath, title: "Old", directory: projectPath)

        #expect(bridge.renameSession(id: sessionID, title: "New"))
        #expect(try programRows(projectPath).first?.title == "New")

        #expect(bridge.renameSession(id: "missing-\(UUID().uuidString)", title: "X") == false)
        #expect(bridge.deleteSession(id: sessionID))
        #expect(try programRows(projectPath, includeArchived: true).isEmpty)
        #expect(bridge.deleteSession(id: sessionID) == false)
    }

    @Test("Открытие чата не двигает updated_at (нет перестановки сайдбара)")
    func unarchivingActiveSessionKeepsTimestamp() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let sessionID = "s1-\(UUID().uuidString)"

        let bridge = DatabaseBridge()
        bridge.createSession(id: sessionID, projectId: projectPath, title: "Chat", directory: projectPath)
        let before = try #require(programRows(projectPath).first { $0.id == sessionID }).updatedAt

        // Выбор сессии разархивирует её. Для уже активной сессии это должно
        // быть no-op — иначе каждый клик переставлял чат вверх списка.
        try DatabaseManager.shared.unarchiveSession(id: sessionID)
        let after = try #require(programRows(projectPath).first { $0.id == sessionID }).updatedAt
        #expect(after == before)

        // Реальный цикл архив/разархив всё же обновляет время.
        try DatabaseManager.shared.archiveSession(id: sessionID)
        try DatabaseManager.shared.unarchiveSession(id: sessionID)
        let restored = try #require(programRows(projectPath, includeArchived: true).first { $0.id == sessionID })
        #expect(restored.isArchived == false)
        #expect(restored.updatedAt >= before)
    }

    @Test("Разархив неизвестного чата — no-op, не падение")
    func unarchivingUnknownSessionDoesNotCrash() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        // Чата нет в базе программы — разархив не должен ронять приложение.
        try DatabaseManager.shared.unarchiveSession(id: "does-not-exist-\(UUID().uuidString)")
        #expect(try programRows(projectPath).isEmpty)
    }
}
