import Testing
import Foundation
@testable import myCoder

@Suite("myCoder paths")
struct MyCoderPathsTests {

    @Test func appDirNameIsMycoder() {
        #expect(MyCoderPaths.appDirName == ".mycoder")
    }

    @Test func bundlePrefixIsMycoder() {
        #expect(MyCoderPaths.bundlePrefix == "com.mycoder")
    }

    @Test func registryPathUsesMycoder() {
        let home = URL(fileURLWithPath: "/tmp/fake-home")
        let url = MyCoderPaths.registryURL(homeDirectory: home)
        #expect(url.path == "/tmp/fake-home/.mycoder/projects.json")
    }

    @Test func projectDataDirUsesMycoder() {
        let url = MyCoderPaths.projectDataDir(projectPath: "/p/x")
        #expect(url.path == "/p/x/.mycoder")
    }

    @Test func legacyRegistryPathUsesMycoder() {
        let home = URL(fileURLWithPath: "/tmp/fake-home")
        let url = MyCoderPaths.registryURL(homeDirectory: home)
        #expect(url.path == "/tmp/fake-home/.mycoder/projects.json")
    }

    @Test func databaseURLUsesMycoder() {
        let home = URL(fileURLWithPath: "/tmp/fake-home")
        let inProject = ProjectDatabaseManager.resolveDatabaseURL(
            projectPath: "/p/x", homeDirectory: home, attemptCreate: { _ in true })
        #expect(inProject.path == "/p/x/.mycoder/project.db")
        let fallback = ProjectDatabaseManager.resolveDatabaseURL(
            projectPath: "/p/x", homeDirectory: home, attemptCreate: { _ in false })
        #expect(fallback.path.hasPrefix("/tmp/fake-home/.mycoder/projects/"))
        #expect(fallback.lastPathComponent == "project.db")
    }

    @Test func projectDataSubdirsUseMycoder() {
        #expect(MyCoderPaths.snapshotsDir(projectPath: "/p/x").path == "/p/x/.mycoder/snapshots")
        #expect(MyCoderPaths.todosURL(projectPath: "/p/x").path == "/p/x/.mycoder/todos.json")
        #expect(MyCoderPaths.backupsDir(projectPath: "/p/x").path == "/p/x/.mycoder/backups")
    }

    @Test func homeDataSubdirsUseMycoder() {
        let home = URL(fileURLWithPath: "/tmp/fake-home")
        #expect(MyCoderPaths.deletedBackupsDir(homeDirectory: home).path == "/tmp/fake-home/.mycoder/deleted-backups")
        #expect(MyCoderPaths.logsDir(homeDirectory: home).path == "/tmp/fake-home/.mycoder/logs")
    }

    @Test func appDataComponentRecognition() {
        #expect(MyCoderPaths.isAppDataPathComponent(".mycoder") == true)
        #expect(MyCoderPaths.isAppDataPathComponent(".git") == false)
        #expect(MyCoderPaths.defaultExcludes.contains(".mycoder"))
    }

    @Test func agentResourceDirsUseMycoder() {
        let home = URL(fileURLWithPath: "/tmp/fake-home")
        #expect(MyCoderPaths.skillsDir(homeDirectory: home).path == "/tmp/fake-home/.mycoder/skills")
        #expect(MyCoderPaths.skillDir(id: "demo", homeDirectory: home).path == "/tmp/fake-home/.mycoder/skills/demo")
        #expect(MyCoderPaths.mcpConfigURL(homeDirectory: home).path == "/tmp/fake-home/.mycoder/mcp.json")
        #expect(MyCoderPaths.commandsDir(homeDirectory: home).path == "/tmp/fake-home/.mycoder/commands")
        #expect(MyCoderPaths.pluginsDir(homeDirectory: home).path == "/tmp/fake-home/.mycoder/plugins")
        #expect(MyCoderPaths.webSessionsDir(providerId: "kimi", homeDirectory: home).path == "/tmp/fake-home/.mycoder/web-sessions/kimi")
        #expect(MyCoderPaths.logFile(name: "api-server.log", homeDirectory: home).path == "/tmp/fake-home/.mycoder/logs/api-server.log")
        #expect(MyCoderPaths.skillsRegistryRelativePath == ".mycoder/skills/registry.json")
        #expect(MyCoderPaths.mcpRegistryRelativePath == ".mycoder/mcp/registry.json")
    }

    @Test func defaultsKeysUseMycoder() {
        let suite = "mycoder-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MyCoderDefaults.key("theme") == "com.mycoder.theme")
        MyCoderDefaults.set("dark", "theme", in: defaults)
        #expect(MyCoderDefaults.string("theme", in: defaults) == "dark")
    }

    @Test func globalDatabaseLivesUnderMycoder() {
        let home = URL(fileURLWithPath: "/tmp/fake-home")
        #expect(MyCoderPaths.globalDatabaseURL(homeDirectory: home).path
            == "/tmp/fake-home/.mycoder/mycoder.db")
    }

    @Test func storageResetPlanUsesMycoder() {
        let home = URL(fileURLWithPath: "/tmp/fake-home")
        let plan = StorageResetLogic.plan(for: .appCacheOnly, homeDirectory: home)
        #expect(plan.deletesPaths == ["/tmp/fake-home/.mycoder/mycoder.db"])
    }
}
