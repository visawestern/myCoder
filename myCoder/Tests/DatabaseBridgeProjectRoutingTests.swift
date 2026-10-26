import Testing
import Foundation
@testable import myCoder

// Serialized because the bridge and project database pool are shared resources.
@Suite("DatabaseBridge — routes session/message storage to per-project databases", .serialized)
struct DatabaseBridgeProjectRoutingTests {

    private func makeTempProjectDir(_ name: String = UUID().uuidString) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-bridge-routing-\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("createSession/loadSessions land in the per-project database when projectId is a real project directory")
    func createAndLoadSessionsRouteToProjectDB() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        DatabaseBridge.shared.createSession(id: "s1", projectId: projectPath, title: "Chat", directory: projectPath)
        let sessions = DatabaseBridge.shared.loadSessions(projectId: projectPath)
        #expect(sessions.map(\.id) == ["s1"])

        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        #expect(try projectDB.getAllSessions().map(\.id) == ["s1"], "session must be physically stored in the per-project database, not the legacy global one")
    }

    @Test("saveMessage/loadMessages route to the owning project database")
    func messagesRouteToActiveProject() throws {
        let projectPath = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(atPath: projectPath)
        }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        DatabaseBridge.shared.createSession(id: "s1", projectId: projectPath, title: "Chat", directory: projectPath)

        let message = Message(id: "m1", role: .user, content: "hello from active project")
        DatabaseBridge.shared.saveMessage(message, sessionId: "s1")

        let loaded = DatabaseBridge.shared.loadMessages(sessionId: "s1")
        #expect(loaded.map(\.content) == ["hello from active project"])

        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        #expect(try projectDB.getMessages(sessionId: "s1").map(\.content) == ["hello from active project"])
    }

    @Test("A failed first send remains visible in the new project's session")
    func failedFirstSendIsPersisted() throws {
        let projectPath = try makeTempProjectDir("failed-send")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        let sessionID = "failed-\(UUID().uuidString)"
        DatabaseBridge.shared.createSession(id: sessionID, projectId: projectPath,
                                            title: "First request", directory: projectPath)
        DatabaseBridge.shared.saveMessage(Message(id: "user-\(UUID().uuidString)", role: .user, content: "hello"), sessionId: sessionID)
        DatabaseBridge.shared.saveMessage(Message(id: "error-\(UUID().uuidString)", role: .assistant, content: "Error: provider unavailable", isFinished: true), sessionId: sessionID)

        let loaded = DatabaseBridge.shared.loadMessages(sessionId: sessionID)
        #expect(loaded.map(\.content) == ["hello", "Error: provider unavailable"])
    }

    @Test("Two project databases isolate message storage")
    func switchingActiveProjectIsolatesMessages() throws {
        let projectA = try makeTempProjectDir("a")
        let projectB = try makeTempProjectDir("b")
        defer {
            try? FileManager.default.removeItem(atPath: projectA)
            try? FileManager.default.removeItem(atPath: projectB)
        }
        ProjectDatabaseManager.evictProject(projectPath: projectA)
        ProjectDatabaseManager.evictProject(projectPath: projectB)

        DatabaseBridge.shared.createSession(id: "sA", projectId: projectA, title: "A", directory: projectA)
        DatabaseBridge.shared.saveMessage(Message(id: "mA", role: .user, content: "in A"), sessionId: "sA")

        DatabaseBridge.shared.createSession(id: "sB", projectId: projectB, title: "B", directory: projectB)
        DatabaseBridge.shared.saveMessage(Message(id: "mB", role: .user, content: "in B"), sessionId: "sB")

        let dbA = try ProjectDatabaseManager.manager(forProjectPath: projectA)
        let dbB = try ProjectDatabaseManager.manager(forProjectPath: projectB)
        #expect(try dbA.getMessages(sessionId: "sA").map(\.content) == ["in A"])
        #expect(try dbB.getMessages(sessionId: "sB").map(\.content) == ["in B"])
        #expect(try dbA.getMessages(sessionId: "sB").isEmpty)
    }

    @Test("archiveSession hides a project session without deleting its data")
    func archiveSessionRoutesToActiveProject() throws {
        let projectPath = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(atPath: projectPath)
        }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        DatabaseBridge.shared.createSession(id: "s1", projectId: projectPath, title: "Chat", directory: projectPath)
        DatabaseBridge.shared.archiveSession(id: "s1")

        #expect(DatabaseBridge.shared.loadSessions(projectId: projectPath).isEmpty)

        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        let archived = try projectDB.getAllSessions(includeArchived: true)
        #expect(archived.map(\.id) == ["s1"], "archived session must still exist on disk")
    }

    @Test("loadSessions returns no sessions for a non-existent project path")
    func loadSessionsFallsBackForInvalidPath() {
        let bogus = "not-a-real-path-\(UUID().uuidString)"
        #expect(DatabaseBridge.shared.loadSessions(projectId: bogus).isEmpty)
    }

    // MARK: - History tail paging (initial load must show the NEWEST page;
    // oldest-first + limit hid every new message once a session outgrew it).

    @Test("tail load returns newest page and older page is disjoint")
    func tailLoadAndOlderPageAreDisjoint() throws {
        let unique = UUID().uuidString
        let projectPath = try makeTempProjectDir("tail-\(unique)")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        let sessionID = "s-tail-\(unique)"
        DatabaseBridge.shared.createSession(id: sessionID, projectId: projectPath, title: "Chat", directory: projectPath)
        var allIDs: [String] = []
        for i in 0..<25 {
            let id = "m-tail-\(unique)-\(i)"
            allIDs.append(id)
            DatabaseBridge.shared.saveMessage(Message(id: id, role: i % 2 == 0 ? .user : .assistant, content: "msg \(i)"), sessionId: sessionID)
        }

        #expect(DatabaseBridge.shared.messageCount(sessionId: sessionID) == 25)

        let tail = DatabaseBridge.shared.loadMessageTail(sessionId: sessionID, take: 20)
        #expect(tail.count == 20)
        #expect(Set(tail.map(\.id)).count == 20, "tail ids must be distinct")
        #expect(Set(tail.map(\.id)).isSubset(of: Set(allIDs)))

        let older = DatabaseBridge.shared.loadOlderPage(sessionId: sessionID, loadedCount: tail.count, pageSize: 20)
        #expect(older.messages.count == 5)
        #expect(older.hasMore == false)
        let tailIDs = Set(tail.map(\.id))
        let olderIDs = Set(older.messages.map(\.id))
        #expect(olderIDs.isDisjoint(with: tailIDs), "older page must not repeat tail rows")
        #expect(tailIDs.union(olderIDs) == Set(allIDs), "tail + older page must cover the whole session")
    }

    @Test("messageCount is zero for unknown sessions and tail is empty")
    func countAndTailHandleUnknownSession() {
        let bogus = "nope-\(UUID().uuidString)"
        #expect(DatabaseBridge.shared.messageCount(sessionId: bogus) == 0)
        #expect(DatabaseBridge.shared.loadMessageTail(sessionId: bogus, take: 20).isEmpty)
        #expect(DatabaseBridge.shared.loadOlderPage(sessionId: bogus, loadedCount: 0, pageSize: 20).messages.isEmpty)
    }

    // MARK: - saveMessagePart routing (audit: stepStart used to bypass the
    // injected inserter and write to the legacy global DB instead of the
    // active project DB).

    @Test("stepStart part is written to the owning project database")
    func stepStartPartRoutesToProjectDB() throws {
        let unique = UUID().uuidString
        let projectPath = try makeTempProjectDir("step-\(unique)")
        defer {
            try? FileManager.default.removeItem(atPath: projectPath)
        }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        DatabaseBridge.shared.createSession(id: "s-step-\(unique)", projectId: projectPath, title: "Chat", directory: projectPath)

        var msg = Message(id: "m-step-\(unique)", role: .assistant, content: "working...")
        msg.parts = [.stepStart, .text("done")]

        DatabaseBridge.shared.saveMessage(msg, sessionId: "s-step-\(unique)")

        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        let parts = try projectDB.getMessageParts(messageId: "m-step-\(unique)")
        #expect(parts.count == 2, "both stepStart and text parts must be in the project DB")
        #expect(parts.first?.type == "step_start", "first part must be step_start, not routed to legacy DB")
    }

    @Test("all part types land in the active project database")
    func allPartTypesRouteToProjectDB() throws {
        let unique = UUID().uuidString
        let projectPath = try makeTempProjectDir("all-\(unique)")
        defer {
            try? FileManager.default.removeItem(atPath: projectPath)
        }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        DatabaseBridge.shared.createSession(id: "s-all-\(unique)", projectId: projectPath, title: "Chat", directory: projectPath)

        var msg = Message(id: "m-all-\(unique)", role: .assistant, content: "")
        msg.parts = [
            .text("hello"),
            .reasoning("thinking"),
            .toolCall(name: "read", args: "{\"f\":\"/x\"}", result: "content", callID: "c1"),
            .stepStart,
            .stepFinish,
            .image(base64: "abc123", mimeType: "image/png")
        ]

        DatabaseBridge.shared.saveMessage(msg, sessionId: "s-all-\(unique)")

        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        let parts = try projectDB.getMessageParts(messageId: "m-all-\(unique)")
        #expect(parts.count == 6, "all 6 parts must be in the project DB")

        let types = parts.map(\.type)
        #expect(types == ["text", "reasoning", "tool_call", "step_start", "step_finish", "image"])
    }

    // MARK: - Temp/global session persistence (Round: tools must survive reload).

    @Test("a temporary session persists its parts and a tool_call part into the global database")
    func tempSessionPersistsPartsIncludingToolCall() throws {
        let unique = UUID().uuidString
        let sessionID = "temp-\(unique)"
        let messageID = "m-temp-\(unique)"

        // No project is ever registered for this session, so saveMessage routes
        // to the global DatabaseManager (the legacy/temp path).
        var msg = Message(id: messageID, role: .assistant, content: "checking...", isFinished: true)
        msg.parts = [
            .text("Запускаю проверку"),
            .toolCall(name: "run_command", args: "{\"command\":\"pwd\"}", result: "/Users/x", callID: "call-\(unique)")
        ]

        DatabaseBridge.shared.saveMessage(msg, sessionId: sessionID)

        let loaded = DatabaseBridge.shared.loadMessages(sessionId: sessionID)
        let restored = loaded.first(where: { $0.id == messageID })
        #expect(restored != nil, "temporary message must be readable back after save")

        let db = DatabaseManager.shared
        let parts = try db.getMessageParts(messageId: messageID)
        #expect(parts.count == 2, "temp session must persist its parts, not just the text content")
        #expect(parts.map(\.type) == ["text", "tool_call"])
        #expect(parts.last?.toolName == "run_command")
        #expect(parts.last?.toolCallId == "call-\(unique)")
    }

    @Test("registerSessionProject binds a session to its project store")
    func registeringSessionProjectBindsStore() throws {
        let projectPath = try makeTempProjectDir("registered")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        let sessionID = "reg-\(UUID().uuidString)"
        let projectDB = try ProjectDatabaseManager.manager(forProjectPath: projectPath)
        try projectDB.insertSession(
            id: sessionID,
            title: "Late chat",
            directory: projectPath,
            branch: nil,
            agentMode: "build",
            modelId: nil,
            providerId: nil
        )
        for index in 0..<10 {
            try projectDB.insertMessage(
                id: "\(sessionID)-m\(index)",
                sessionId: sessionID,
                role: "user",
                content: "message \(index)"
            )
        }

        DatabaseBridge.shared.registerSessionProject(sessionID: sessionID, projectPath: projectPath)

        let tail = DatabaseBridge.shared.loadMessageTail(sessionId: sessionID, take: 4)
        #expect(tail.map(\.content) == (6...9).map { "message \($0)" },
                "the newest 4 messages load, oldest-first")
        #expect(DatabaseBridge.shared.messageCount(sessionId: sessionID) == 10)
    }
}
