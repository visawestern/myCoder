import XCTest
@testable import myCoder

/// После полного сброса базы (`.fullDatabase`) список чатов в сайдбаре
/// должен обновиться: все sidebar-кэши (проектные + без-проектные) обязаны
/// очиститься, иначе сайдбар продолжит показывать старые чаты из памяти
/// (баг-репорт 2026-10-30: «при обнулении базы полностью не обновляет
/// список чатов»).
@MainActor
final class StorageResetSidebarTests: XCTestCase {

    private func makeSandbox() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reset-sidebar-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func seedSidebarState(_ appState: AppState) {
        let ws = Workspace(id: "w1", name: "One", path: "/tmp/one", tasks: [])
        appState.selectedWorkspace = ws
        let session = ChatSession(
            id: "s1",
            title: "Old chat",
            createdAt: Date(),
            updatedAt: Date(),
            directory: "/tmp/one",
            branch: nil,
            gitSummary: nil,
            sessionGoal: nil,
            modelID: nil,
            providerID: nil,
            parentSessionID: nil,
            subagentStatus: nil
        )
        // Приватный кэш заполняем через публичный API сайдбара.
        appState.updateSidebarSessions(projectID: "w1", sessions: [session])
        appState.updateSidebarProjectlessSessions([session])
    }

    func testFullResetClearsSidebarSessionCaches() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let appState = AppState()
        seedSidebarState(appState)

        appState.resetStorage(
            scope: .fullDatabase,
            homeDirectory: sandbox,
            resetDatabase: { /* no-op: не трогаем реальную БД */ }
        )

        XCTAssertTrue(
            appState.sidebarProjectSessions.isEmpty,
            "проектные чаты должны быть очищены после полного сброса"
        )
        XCTAssertTrue(
            appState.sidebarProjectlessSessions.isEmpty,
            "без-проектные чаты должны быть очищены после полного сброса"
        )
        XCTAssertNil(appState.selectedWorkspace)
        XCTAssertNil(appState.selectedSession)
        XCTAssertTrue(appState.sessions.isEmpty)
    }

    func testFullResetThenReloadLoadsEmptyChats() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let appState = AppState()
        seedSidebarState(appState)

        appState.resetStorage(
            scope: .fullDatabase,
            homeDirectory: sandbox,
            resetDatabase: { /* no-op */ }
        )

        // После сброса повторная загрузка сайдбара должна дать пустой список
        // (кэш очищен → loadSidebarSessions перечитает БД).
        let ws = Workspace(id: "w1", name: "One", path: "/tmp/one", tasks: [])
        XCTAssertTrue(appState.sidebarSessions(for: ws).isEmpty)
    }
}
