import Testing
import Foundation
@testable import myCoder

/// Session routing must survive an app launch and must not split one
/// conversation across two stores. The in-memory route map is rebuilt on every
/// launch, so the durable route row and the discovery across registered
/// projects are what keep a session bound to its project database.
@Suite("Session routing — durable route and global-tail recovery", .serialized)
@MainActor
struct SessionRouteRecoveryTests {

    private func makeTempProjectDir(_ name: String = UUID().uuidString) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-route-\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private func registerProjectInGlobalRegistry(_ projectPath: String) throws {
        let normalized = ChatSession.normalizedPath(projectPath)
        try DatabaseManager.shared.insertProject(id: normalized, name: "Route test", path: normalized)
    }

    @Test("A durable route resolves the project store after the in-memory map is gone")
    func durableRouteResolvesAfterRestart() throws {
        let projectPath = try makeTempProjectDir("durable")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)
        // Deliberately NOT registered in the global project registry: the
        // durable route row must be the only way back to this store.

        let sessionID = "durable-\(UUID().uuidString)"
        DatabaseBridge.shared.createSession(
            id: sessionID,
            projectId: projectPath,
            title: "Durable chat",
            directory: projectPath
        )
        DatabaseBridge.shared.saveMessage(
            Message(id: "\(sessionID)-m1", role: .user, content: "stored in project", isFinished: true),
            sessionId: sessionID
        )

        // Simulate an app launch: the in-memory route map is rebuilt empty,
        // only the durable row survives.
        DatabaseBridge.shared.forgetSessionProject(sessionID: sessionID)
        try DatabaseManager.shared.deleteSessionRoute(sessionId: sessionID)

        // Without any route the session resolves to no project store…
        #expect(DatabaseBridge.shared.loadMessageTail(sessionId: sessionID, take: 10).isEmpty)

        // …but a route row written at creation time brings it back.
        try DatabaseManager.shared.setSessionRoute(sessionId: sessionID, projectPath: projectPath)
        let tail = DatabaseBridge.shared.loadMessageTail(sessionId: sessionID, take: 10)
        #expect(tail.map(\.content) == ["stored in project"])
    }

    @Test("Discovery finds the owning project of a session that has no route row")
    func discoveryFindsOwningProject() throws {
        let projectPath = try makeTempProjectDir("discover")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)
        try registerProjectInGlobalRegistry(projectPath)

        let sessionID = "discover-\(UUID().uuidString)"
        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        try projectDB.insertSession(
            id: sessionID,
            title: "Old chat",
            directory: projectPath,
            branch: nil,
            agentMode: "build",
            modelId: nil,
            providerId: nil
        )
        try projectDB.insertMessage(
            id: "\(sessionID)-m1",
            sessionId: sessionID,
            role: "user",
            content: "written before the route existed",
            createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 120)
        )

        // No route row at all: the session must still resolve to its project.
        DatabaseBridge.shared.forgetSessionProject(sessionID: sessionID)

        let tail = DatabaseBridge.shared.loadMessageTail(sessionId: sessionID, take: 10)
        #expect(tail.map(\.content) == ["written before the route existed"],
                "discovery must find the project that owns the session")
        #expect(try DatabaseManager.shared.sessionRoute(sessionId: sessionID) == projectPath,
                "a discovered route is persisted so the next launch is cheap")
    }

    @Test("A conversation split across both stores is healed into one stream")
    func globalTailIsRecoveredIntoProjectStore() throws {
        let projectPath = try makeTempProjectDir("recover")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)
        try registerProjectInGlobalRegistry(projectPath)

        let sessionID = "recover-\(UUID().uuidString)"
        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        try projectDB.insertSession(
            id: sessionID,
            title: "Split chat",
            directory: projectPath,
            branch: nil,
            agentMode: "build",
            modelId: nil,
            providerId: nil
        )
        for index in 0..<3 {
            try projectDB.insertMessage(
                id: "\(sessionID)-old\(index)",
                sessionId: sessionID,
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "old \(index)",
                createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 300 + Double(index))
            )
        }
        // The newest part of the conversation was written while the route was
        // unknown, so it landed in the global store.
        for index in 0..<2 {
            try DatabaseManager.shared.insertMessage(
                id: "\(sessionID)-new\(index)",
                sessionId: sessionID,
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "new \(index)"
            )
        }
        DatabaseBridge.shared.forgetSessionProject(sessionID: sessionID)

        let store = MessageStore()
        store.loadFromDatabase(sessionId: sessionID, limit: 20)

        #expect(store.messages.map(\.content) == ["old 0", "old 1", "old 2", "new 0", "new 1"],
                "the recovered tail must continue the same conversation, in order")
        #expect(store.hasMoreMessages == false)
        #expect(try DatabaseManager.shared.getMessagesBySession(sessionId: sessionID).isEmpty,
                "the global copy is removed once the message lives in the project store")
        #expect(try projectDB.getMessages(sessionId: sessionID).count == 5)
    }

    @Test("A project session that also has a global sessions row reads from the project store")
    func globalSessionRowDoesNotStealProjectHistory() throws {
        let projectPath = try makeTempProjectDir("shadow")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)
        try registerProjectInGlobalRegistry(projectPath)

        let sessionID = "shadow-\(UUID().uuidString)"
        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        try projectDB.insertSession(
            id: sessionID,
            title: "Shadowed chat",
            directory: projectPath,
            branch: nil,
            agentMode: "build",
            modelId: nil,
            providerId: nil
        )
        try projectDB.insertMessage(
            id: "\(sessionID)-m1",
            sessionId: sessionID,
            role: "user",
            content: "history lives in the project store"
        )
        // The global sessions table also knows this session (it was created
        // there before the project was resolved) — the row must not redirect
        // the read to the global database, which holds no messages.
        try DatabaseManager.shared.insertSession(
            id: sessionID,
            projectId: "",
            title: "Shadowed chat",
            directory: ""
        )

        DatabaseBridge.shared.forgetSessionProject(sessionID: sessionID)

        let tail = DatabaseBridge.shared.loadMessageTail(sessionId: sessionID, take: 10)
        #expect(tail.map(\.content) == ["history lives in the project store"],
                "the project store wins over a leftover global sessions row")
    }

    @Test("Unknown paths are not routed to a project database")
    func unknownPathIsNotRegistered() throws {
        let sessionID = "unknown-\(UUID().uuidString)"
        let randomPath = try makeTempProjectDir("unknown")

        DatabaseBridge.shared.registerSessionProjectIfKnown(
            sessionID: sessionID,
            projectPath: randomPath
        )

        #expect(DatabaseBridge.shared.loadMessageTail(sessionId: sessionID, take: 10).isEmpty)
        #expect(!ProjectDatabaseManager.hasExistingDatabase(projectPath: randomPath),
                "registering an unknown path must not create a project database")
    }
}
