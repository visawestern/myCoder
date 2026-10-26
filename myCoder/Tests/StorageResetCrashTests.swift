import XCTest
@testable import myCoder

final class StorageResetCrashTests: XCTestCase {

    // Round 10 real claim: the crash happens when resetStorage() is called
    // while the navigation index is out of bounds (didSet during reset).
    // The current implementation does not reproduce the crash, but these
    // tests pin the invariant that nuclear-state clearing must keep the
    // navigation stack consistent.
    //
    // Round 14 (test-safety): these tests used to call
    // `resetStorage(scope: .appCacheOnly)` with default args, which deleted
    // the REAL user's ~/.mycoder/mimo.db and dropped every table via
    // `DatabaseManager.shared.reset()`. They now run in a temp sandbox with a
    // no-op database reset, so running the test suite can never destroy real
    // user data (devil's-advocate re-audit 2026-08-01).

    /// A temp home + no-op DB reset so the test exercises the SAME code path
    /// (plan computation, deletion loop, in-memory clearing) without touching
    /// the real home directory or the real singleton database.
    private func makeSandbox() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reset-crash-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sandboxedReset(_ appState: AppState, sandbox: URL) {
        appState.resetStorage(
            scope: .appCacheOnly,
            homeDirectory: sandbox,
            resetDatabase: { /* no-op: never touch the real DatabaseManager.shared */ }
        )
    }

    func testNavigationIndexBoundsAfterResetStorage() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let appState = AppState()
        let ws1 = Workspace(id: "w1", name: "One", path: "/tmp/one", tasks: [])
        let ws2 = Workspace(id: "w2", name: "Two", path: "/tmp/two", tasks: [])
        // Simulate browsing back/forward.
        appState.selectedWorkspace = ws1
        appState.selectedWorkspace = ws2
        appState.navigateBack()
        appState.navigateForward()
        // Now reset — the didSet will mutate navigationHistory.
        sandboxedReset(appState, sandbox: sandbox)
        XCTAssertNil(appState.selectedWorkspace)
        XCTAssertNil(appState.selectedSession)
        XCTAssertTrue(appState.navigationHistory.isEmpty)
        XCTAssertEqual(appState.navigationIndex, -1)
    }

    func testResetStorageMultipleTimes() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let appState = AppState()
        appState.selectedWorkspace = Workspace(id: "w1", name: "A", path: "/tmp/a", tasks: [])
        // Call twice — second call must not crash.
        sandboxedReset(appState, sandbox: sandbox)
        sandboxedReset(appState, sandbox: sandbox)
        XCTAssertTrue(appState.navigationHistory.isEmpty)
        XCTAssertEqual(appState.navigationIndex, -1)
    }

    func testResetStorageLeavesSettingsIntact() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let appState = AppState()
        let settings = appState.settings
        sandboxedReset(appState, sandbox: sandbox)
        XCTAssertEqual(appState.settings.httpProxy, settings.httpProxy)
        XCTAssertEqual(appState.settings.language, settings.language)
    }
}
