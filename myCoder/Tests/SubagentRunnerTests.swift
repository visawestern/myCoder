import Testing
import Foundation
@testable import myCoder

@Suite("SubagentRunner — sessions, lifecycle and gating", .serialized)
struct SubagentRunnerTests {

    private func makeTempProjectDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("Child sessions persist in the project database with parent and status")
    func childSessionLifecycleInProjectDB() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let manager = try ProjectDatabaseManager.manager(forProjectPath: projectPath)

        let childID = UUID().uuidString
        try manager.insertSession(
            id: childID,
            title: "Investigate the parser",
            directory: projectPath,
            parentSessionId: "parent-1",
            subagentStatus: SubagentRunner.statusRunning
        )
        try manager.insertSession(
            id: UUID().uuidString,
            title: "Regular chat",
            directory: projectPath
        )

        let children = try manager.childSessions(parentId: "parent-1")
        #expect(children.count == 1)
        #expect(children.first?.title == "Investigate the parser")
        #expect(children.first?.parentSessionId == "parent-1")
        #expect(children.first?.subagentStatus == SubagentRunner.statusRunning)

        try manager.setSubagentStatus(id: childID, status: SubagentRunner.statusDone)
        let updated = try manager.childSessions(parentId: "parent-1")
        #expect(updated.first?.subagentStatus == SubagentRunner.statusDone)
    }

    @Test("Child sessions persist in the global store for standalone chats")
    func childSessionLifecycleInGlobalDB() throws {
        let db = DatabaseManager(inMemory: true)
        let childID = UUID().uuidString
        try db.insertSession(
            id: childID,
            projectId: ChatSession.standaloneProjectKey,
            title: "Explore modules",
            directory: ChatSession.standaloneProjectKey,
            parentSessionId: "standalone-parent",
            subagentStatus: SubagentRunner.statusRunning
        )
        defer {
            _ = try? db.deleteSession(id: childID)
        }

        let children = try db.childSessions(parentId: "standalone-parent")
        #expect(children.count >= 1)
        let mine = children.first { $0.id == childID }
        #expect(mine?.parentSessionId == "standalone-parent")
        #expect(mine?.subagentStatus == SubagentRunner.statusRunning)
        #expect(mine?.projectId == ChatSession.standaloneProjectKey)

        try db.setSubagentStatus(sessionId: childID, status: SubagentRunner.statusFailed)
        let failed = try db.childSessions(parentId: "standalone-parent")
        #expect(failed.first { $0.id == childID }?.subagentStatus == SubagentRunner.statusFailed)
    }

    @Test("Sidebar mapping hides child sessions, child loading exposes them")
    func bridgeMappingFiltersChildren() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let bridge = DatabaseBridge.shared
        bridge.createSession(id: UUID().uuidString, projectId: projectPath, title: "Parent", directory: projectPath)
        let child = bridge.createSubagentSession(
            parentSessionID: "bridge-parent",
            projectKey: projectPath,
            directory: projectPath,
            title: "Child subagent"
        )

        let children = bridge.loadChildSessions(parentID: "bridge-parent", projectKey: projectPath)
        #expect(children.contains { $0.id == child.id })
        #expect(children.first { $0.id == child.id }?.subagentStatus == SubagentRunner.statusRunning)

        let sidebar = bridge.loadSessions(projectId: projectPath)
        #expect(!sidebar.contains { $0.id == child.id })
        #expect(!sidebar.contains { $0.parentSessionID != nil })

        bridge.setSubagentStatus(sessionID: child.id, status: SubagentRunner.statusDone)
        let done = bridge.loadChildSessions(parentID: "bridge-parent", projectKey: projectPath)
        #expect(done.first { $0.id == child.id }?.subagentStatus == SubagentRunner.statusDone)
    }

    @Test("Titles are trimmed to the display budget")
    func titleGeneration() {
        #expect(SubagentRunner.title(for: "Investigate the parser bug") == "Investigate the parser bug")
        #expect(SubagentRunner.title(for: "  \n ") == "Sub-agent")
        let long = String(repeating: "a", count: 200)
        let title = SubagentRunner.title(for: long)
        #expect(title.count == SubagentRunner.maxTitleLength)
        #expect(title.hasSuffix("…"))
    }

    @Test("Only read-only tools may execute inside a sub-agent")
    func readOnlyGating() {
        #expect(SubagentRunner.isReadOnly(WebToolCall(name: "read_file", arguments: ["path": "a.md"])))
        #expect(SubagentRunner.isReadOnly(WebToolCall(name: "Read", arguments: ["path": "a.md"])))
        #expect(SubagentRunner.isReadOnly(WebToolCall(name: "git_status", arguments: [:])))
        #expect(!SubagentRunner.isReadOnly(WebToolCall(name: "write_file", arguments: [:])))
        #expect(!SubagentRunner.isReadOnly(WebToolCall(name: "run_command", arguments: [:])))
        #expect(!SubagentRunner.isReadOnly(WebToolCall(name: "git_push", arguments: [:])))
        #expect(!SubagentRunner.isReadOnly(WebToolCall(name: "edit_file", arguments: [:])))
    }
}
