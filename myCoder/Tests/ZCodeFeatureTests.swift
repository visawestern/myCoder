import Testing
import Foundation
@testable import myCoder

@Suite("Workspace Model")
struct WorkspaceModelTests {

    @Test("Workspace decodes from JSON")
    func decodeWorkspace() throws {
        let json = """
        {
            "id": "ws_1",
            "name": "tm3",
            "path": "/Users/test/tm3",
            "branch": "razum-v4",
            "tasks": []
        }
        """
        let data = json.data(using: .utf8)!
        let ws = try JSONDecoder().decode(Workspace.self, from: data)
        #expect(ws.id == "ws_1")
        #expect(ws.name == "tm3")
        #expect(ws.branch == "razum-v4")
    }

    @Test("Workspace with tasks")
    func workspaceWithTasks() throws {
        let task = WorkspaceTask(id: "t1", title: "Test task", status: .pending, duration: "3d")
        let ws = Workspace(id: "ws_1", name: "tm3", path: "/test", branch: "main", tasks: [task])
        #expect(ws.tasks.count == 1)
        #expect(ws.tasks[0].title == "Test task")
    }
}

@Suite("Settings Model")
struct SettingsModelTests {

    @Test("AppSettings default values")
    func defaultSettings() {
        let settings = AppSettings()
        #expect(settings.theme == .dark)
        #expect(settings.language == "English")
        #expect(settings.zoom == .default)
        #expect(settings.showLineNumbers == true)
        #expect(settings.wrapLongLines == true)
        #expect(settings.codeFontSize == 12)
    }

    @Test("AppSettings encoding roundtrip")
    func settingsRoundtrip() throws {
        var settings = AppSettings()
        settings.theme = .light
        settings.language = "Russian"
        settings.zoom = .larger
        settings.showLineNumbers = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.theme == .light)
        #expect(decoded.language == "Russian")
        #expect(decoded.zoom == .larger)
        #expect(decoded.showLineNumbers == false)
    }
}

@Suite("Access Level Model")
struct AccessLevelTests {

    @Test("AccessLevel cases")
    func accessLevelCases() {
        let levels: [AccessLevel] = [.askBeforeChanges, .editAutomatically, .fullAccess]
        #expect(levels.count == 3)
        #expect(levels.last == .fullAccess)
    }

    @Test("Variant migration from legacy thinking levels")
    func variantMigration() {
        #expect(ProviderSettingsLogic.migrateLegacyThinkingLevel("Max") == "high")
    }
}

@Suite("Git Changes Model")
struct GitChangesTests {

    @Test("GitChanges computes net")
    func gitChangesNet() {
        let changes = GitChanges(additions: 736, deletions: 130)
        #expect(changes.net == 606)
        #expect(changes.formatted == "+736 -130")
    }

    @Test("FileChange model")
    func fileChangeModel() {
        let file = FileChange(path: "Sources/main.swift", additions: 10, deletions: 3, status: .edited)
        #expect(file.status == .edited)
        #expect(file.displayStatus == "Edited")
    }
}

@Suite("Progress Model")
struct ProgressTests {

    @Test("TaskProgress computes completion")
    func taskProgressCompletion() {
        let steps = [
            TaskStep(title: "Step 1", status: .completed),
            TaskStep(title: "Step 2", status: .inProgress),
            TaskStep(title: "Step 3", status: .waiting)
        ]
        let progress = TaskProgress(steps: steps)
        #expect(progress.completedCount == 1)
        #expect(progress.totalCount == 3)
        #expect(progress.formatted == "1/3")
    }
}
