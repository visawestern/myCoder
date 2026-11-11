import Testing
import Foundation
@testable import myCoder

// Serialized because the bridge and program database are shared resources.
@MainActor
@Suite("DatabaseBridge — chats live in the program database (user directive 2026-10-29)", .serialized)
struct DatabaseBridgeProjectRoutingTests {

    private func makeTempProjectDir(_ name: String = UUID().uuidString) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-bridge-routing-\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("createSession/loadSessions store the chat in the program database, not a project file")
    func createAndLoadSessionsLiveInProgramDatabase() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let sessionID = "s1-\(UUID().uuidString)"

        DatabaseBridge.shared.createSession(id: sessionID, projectId: projectPath, title: "Chat", directory: projectPath)
        let sessions = DatabaseBridge.shared.loadSessions(projectId: projectPath)
        #expect(sessions.map(\.id) == [sessionID])

        // No per-project database file may be created for chat storage.
        #expect(!ProjectDatabaseManager.hasExistingDatabase(projectPath: projectPath),
                "chat storage must never create a database inside the project folder")
        // The session row lives in the program database, keyed by the project.
        let programDB = DatabaseManager.shared
        #expect(try programDB.getSessionsByProject(projectId: ChatSession.normalizedPath(projectPath)).map(\.id) == [sessionID])
    }

    @Test("saveMessage/loadMessages route to the program database")
    func messagesRouteToProgramDatabase() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let sessionID = "s1-\(UUID().uuidString)"

        DatabaseBridge.shared.createSession(id: sessionID, projectId: projectPath, title: "Chat", directory: projectPath)
        DatabaseBridge.shared.saveMessage(Message(id: "m1-\(UUID().uuidString)", role: .user, content: "hello from program db"), sessionId: sessionID)

        let loaded = DatabaseBridge.shared.loadMessages(sessionId: sessionID)
        #expect(loaded.map(\.content) == ["hello from program db"])

        #expect(!ProjectDatabaseManager.hasExistingDatabase(projectPath: projectPath),
                "messages must be stored in the program database, not a project file")
    }

    @Test("a failed first send remains visible in the new project's session")
    func failedFirstSendIsPersisted() throws {
        let projectPath = try makeTempProjectDir("failed-send")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let sessionID = "failed-\(UUID().uuidString)"
        DatabaseBridge.shared.createSession(id: sessionID, projectId: projectPath, title: "First request", directory: projectPath)
        DatabaseBridge.shared.saveMessage(Message(id: "user-\(UUID().uuidString)", role: .user, content: "hello"), sessionId: sessionID)
        DatabaseBridge.shared.saveMessage(Message(id: "error-\(UUID().uuidString)", role: .assistant, content: "Error: provider unavailable", isFinished: true), sessionId: sessionID)

        let loaded = DatabaseBridge.shared.loadMessages(sessionId: sessionID)
        #expect(loaded.map(\.content) == ["hello", "Error: provider unavailable"])
    }

    @Test("chats of different projects are isolated by project key in the program database")
    func projectsIsolateChatsByKey() throws {
        let projectA = try makeTempProjectDir("a")
        let projectB = try makeTempProjectDir("b")
        defer {
            try? FileManager.default.removeItem(atPath: projectA)
            try? FileManager.default.removeItem(atPath: projectB)
        }

        DatabaseBridge.shared.createSession(id: "sA", projectId: projectA, title: "A", directory: projectA)
        DatabaseBridge.shared.saveMessage(Message(id: "mA", role: .user, content: "in A"), sessionId: "sA")

        DatabaseBridge.shared.createSession(id: "sB", projectId: projectB, title: "B", directory: projectB)
        DatabaseBridge.shared.saveMessage(Message(id: "mB", role: .user, content: "in B"), sessionId: "sB")

        #expect(DatabaseBridge.shared.loadSessions(projectId: projectA).map(\.id) == ["sA"])
        #expect(DatabaseBridge.shared.loadSessions(projectId: projectB).map(\.id) == ["sB"])
        #expect(DatabaseBridge.shared.loadMessages(sessionId: "sA").map(\.content) == ["in A"])
        #expect(DatabaseBridge.shared.loadMessages(sessionId: "sB").map(\.content) == ["in B"])
    }

    @Test("archiveSession hides a project chat without deleting its data")
    func archiveSessionHidesChat() throws {
        let projectPath = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let sessionID = "s1-\(UUID().uuidString)"

        DatabaseBridge.shared.createSession(id: sessionID, projectId: projectPath, title: "Chat", directory: projectPath)
        DatabaseBridge.shared.archiveSession(id: sessionID)

        #expect(DatabaseBridge.shared.loadSessions(projectId: projectPath).isEmpty)
        // The archived row still exists in the program database.
        #expect(try DatabaseManager.shared.getSessionsByProject(projectId: ChatSession.normalizedPath(projectPath), includeArchived: true).map(\.id) == [sessionID])
    }

    @Test("loadSessions returns no sessions for a non-existent project path")
    func loadSessionsEmptyForInvalidPath() {
        let bogus = "not-a-real-path-\(UUID().uuidString)"
        #expect(DatabaseBridge.shared.loadSessions(projectId: bogus).isEmpty)
    }

    // MARK: - History tail paging

    @Test("tail load returns newest page and older page is disjoint")
    func tailLoadAndOlderPageAreDisjoint() throws {
        let unique = UUID().uuidString
        let projectPath = try makeTempProjectDir("tail-\(unique)")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

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
        #expect(Set(tail.map(\.id)).count == 20)
        #expect(Set(tail.map(\.id)).isSubset(of: Set(allIDs)))

        let older = DatabaseBridge.shared.loadOlderPage(sessionId: sessionID, loadedCount: tail.count, pageSize: 20)
        #expect(older.messages.count == 5)
        #expect(older.hasMore == false)
        #expect(Set(older.messages.map(\.id)).isDisjoint(with: Set(tail.map(\.id))))
        #expect(Set(tail.map(\.id)).union(Set(older.messages.map(\.id))) == Set(allIDs))
    }

    @Test("messageCount is zero for unknown sessions and tail is empty")
    func countAndTailHandleUnknownSession() {
        let bogus = "nope-\(UUID().uuidString)"
        #expect(DatabaseBridge.shared.messageCount(sessionId: bogus) == 0)
        #expect(DatabaseBridge.shared.loadMessageTail(sessionId: bogus, take: 20).isEmpty)
        #expect(DatabaseBridge.shared.loadOlderPage(sessionId: bogus, loadedCount: 0, pageSize: 20).messages.isEmpty)
    }

    // MARK: - Message parts

    @Test("all part types land in the program database")
    func allPartTypesRouteToProgramDatabase() throws {
        let unique = UUID().uuidString
        let projectPath = try makeTempProjectDir("all-\(unique)")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

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

        let parts = try DatabaseManager.shared.getMessageParts(messageId: "m-all-\(unique)")
        #expect(parts.count == 6)
        #expect(parts.map(\.type) == ["text", "reasoning", "tool_call", "step_start", "step_finish", "image"])
    }

    @Test("sendInfo (модель/параметры) сохраняется и возвращается из БД")
    func sendInfoRoundTripsThroughDatabase() throws {
        let unique = UUID().uuidString
        let projectPath = try makeTempProjectDir("sendinfo-\(unique)")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }
        let sessionID = "s-sendinfo-\(unique)"
        let messageID = "m-sendinfo-\(unique)"

        DatabaseBridge.shared.createSession(id: sessionID, projectId: projectPath, title: "Chat", directory: projectPath)
        let info = MessageSendInfo(
            modelID: "beam",
            providerID: "0AAC5E83",
            temperature: 0.7,
            topP: 0.9,
            maxTokens: 1024,
            systemPrompt: "You are helpful",
            variant: "high",
            tools: ["read_file", "list_dir"],
            sentAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let message = Message(id: messageID, role: .user, content: "hi", isFinished: true, sendInfo: info)
        DatabaseBridge.shared.saveMessage(message, sessionId: sessionID)

        // Metadata JSON must be physically stored in the messages row.
        let records = try DatabaseManager.shared.getMessagesBySession(sessionId: sessionID)
        #expect(records.first?.metadata != nil)
        #expect(records.first?.metadata?.contains("beam") == true)

        let loaded = DatabaseBridge.shared.loadMessages(sessionId: sessionID)
        #expect(loaded.first?.sendInfo == info)
    }

    @Test("a standalone (project-less) session persists parts in the program database")
    func standaloneSessionPersistsPartsIncludingToolCall() throws {
        let unique = UUID().uuidString
        let sessionID = "temp-\(unique)"
        let messageID = "m-temp-\(unique)"

        DatabaseBridge.shared.createSession(id: sessionID, projectId: ChatSession.standaloneProjectKey, title: "Standalone", directory: "")
        var msg = Message(id: messageID, role: .assistant, content: "checking...", isFinished: true)
        msg.parts = [
            .text("Запускаю проверку"),
            .toolCall(name: "run_command", args: "{\"command\":\"pwd\"}", result: "/Users/x", callID: "call-\(unique)")
        ]
        DatabaseBridge.shared.saveMessage(msg, sessionId: sessionID)

        let loaded = DatabaseBridge.shared.loadMessages(sessionId: sessionID)
        let restored = loaded.first(where: { $0.id == messageID })
        #expect(restored != nil)
        #expect(restored?.parts.count == 2)

        let parts = try DatabaseManager.shared.getMessageParts(messageId: messageID)
        #expect(parts.map(\.type) == ["text", "tool_call"])
        #expect(parts.last?.toolName == "run_command")
        #expect(parts.last?.toolCallId == "call-\(unique)")
    }
}
