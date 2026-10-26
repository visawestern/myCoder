import Testing
import Foundation
@testable import myCoder

@Suite("Chat navigator numbers the whole session", .serialized)
struct ChatNavigatorNumberingTests {

    private func makeTempProjectDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-navigator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("Button titles continue from the offset")
    func buttonTitleUsesOffset() {
        #expect(UserMessageNavigatorLogic.buttonTitle(index: 0) == "1")
        #expect(UserMessageNavigatorLogic.buttonTitle(index: 0, offset: 10) == "11")
        #expect(UserMessageNavigatorLogic.buttonTitle(index: 9, offset: 10) == "20")
    }

    @Test("Only user messages with content are counted")
    func countsUserMessages() {
        let messages = [
            Message(id: "1", role: .user, content: "first"),
            Message(id: "2", role: .assistant, content: "answer"),
            Message(id: "3", role: .user, content: "   "),
            Message(id: "4", role: .user, content: "second"),
        ]
        #expect(UserMessageNavigatorLogic.userMessageCount(messages) == 2)
    }

    @Test("The offset counts the user messages outside the loaded page")
    @MainActor
    func storeOffsetCoversOlderMessages() throws {
        let projectPath = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(atPath: projectPath)
            ProjectDatabaseManager.evictProject(projectPath: projectPath)
        }
        ProjectDatabaseManager.evictProject(projectPath: projectPath)

        let sessionID = "navigator-\(UUID().uuidString)"
        DatabaseBridge.shared.createSession(
            id: sessionID,
            projectId: projectPath,
            title: "Chat",
            directory: projectPath
        )
        for index in 0..<6 {
            DatabaseBridge.shared.saveMessage(
                Message(id: "user-\(index)", role: .user, content: "question \(index)"),
                sessionId: sessionID
            )
            DatabaseBridge.shared.saveMessage(
                Message(id: "assistant-\(index)", role: .assistant, content: "answer \(index)"),
                sessionId: sessionID
            )
        }

        let store = MessageStore()
        store.loadFromDatabase(sessionId: sessionID, limit: 4)
        #expect(store.messages.count == 4)
        #expect(store.olderUserMessageCount == 4)

        store.loadOlderFromDatabase(sessionId: sessionID, pageSize: 20)
        #expect(store.messages.count == 12)
        #expect(store.olderUserMessageCount == 0)
    }
}
