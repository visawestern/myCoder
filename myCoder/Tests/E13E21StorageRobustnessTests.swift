import Testing
import Foundation
@testable import myCoder

/// E13 (Раздел 8 п.51): a project on a read-only/system-protected path (where
/// `<project>/.mycoder/` cannot be created) must still open — the DB falls
/// back to `<home>/.mycoder/projects/<stable-hash>/project.db` instead of the
/// whole open failing. E21 (Раздел 7 п.46): per-project DBs run in WAL mode.
@Suite("E13/E21 — read-only fallback + WAL journaling (Round 24)")
struct E13E21StorageRobustnessTests {

    private func makeTempBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("e13e21-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - E13: fallback location decision (pure, deterministic)

    @Test("writable project keeps the DB inside the project .mycoder dir")
    func writableProjectStaysInProject() {
        let home = URL(fileURLWithPath: "/tmp/home")
        let url = ProjectDatabaseManager.resolveDatabaseURL(
            projectPath: "/Users/me/Work/MyApp", homeDirectory: home,
            attemptCreate: { _ in true })
        #expect(url.path == "/Users/me/Work/MyApp/.mycoder/project.db")
    }

    @Test("read-only project falls back to the hashed home location")
    func readOnlyFallsBackToHashedHome() {
        let home = URL(fileURLWithPath: "/tmp/home")
        let url = ProjectDatabaseManager.resolveDatabaseURL(
            projectPath: "/System/Protected/Path", homeDirectory: home,
            attemptCreate: { _ in false })
        #expect(url.lastPathComponent == "project.db")
        #expect(url.path.hasPrefix("/tmp/home/.mycoder/projects/"),
                "fallback DB must live under <home>/.mycoder/projects/<hash>/project.db, got \(url.path)")
        #expect(!url.path.contains("/System/Protected/Path"),
                "fallback must not reference the un-writable in-project location")
    }

    @Test("fallback hash is stable per project path")
    func fallbackHashIsStable() {
        let home = URL(fileURLWithPath: "/tmp/home")
        let a = ProjectDatabaseManager.resolveDatabaseURL(
            projectPath: "/System/Protected/Path", homeDirectory: home,
            attemptCreate: { _ in false })
        let b = ProjectDatabaseManager.resolveDatabaseURL(
            projectPath: "/System/Protected/Path", homeDirectory: home,
            attemptCreate: { _ in false })
        #expect(a == b)
    }

    // MARK: - E13: end-to-end on a real read-only directory

    @Test("a real read-only project opens via fallback without creating .mycoder in-project")
    func readOnlyProjectOpensViaFallback() throws {
        let base = try makeTempBase()
        let projectDir = base.appendingPathComponent("ro-project")
        let home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: projectDir.path)
            try? FileManager.default.removeItem(at: base)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555],
                                              ofItemAtPath: projectDir.path)

        let manager = try ProjectDatabaseManager.open(projectPath: projectDir.path, homeDirectory: home)
        #expect(!FileManager.default.fileExists(
            atPath: projectDir.appendingPathComponent(".mycoder").path),
            "E13: open() must not create .mycoder inside a read-only project")
        #expect(manager.databaseFileURL.path.hasPrefix(home.path + "/.mycoder/projects/"))
        #expect(FileManager.default.fileExists(atPath: manager.databaseFileURL.path),
                "the fallback DB file must actually exist and be usable")
    }

    // MARK: - E21: WAL journal mode

    @Test("per-project DB opens in WAL journal mode")
    func projectDBUsesWAL() throws {
        let base = try makeTempBase()
        let projectDir = base.appendingPathComponent("wal-project")
        let home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let manager = try ProjectDatabaseManager.open(projectPath: projectDir.path, homeDirectory: home)
        #expect(manager.journalMode == "wal",
                "project.db must run in WAL mode, got \(manager.journalMode ?? "nil")")
    }
}
