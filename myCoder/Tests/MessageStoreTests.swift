import Testing
import Foundation
@testable import myCoder

@Suite("MessageStore")
struct MessageStoreTests {
    @Test("History opens with twenty messages and grows by pages")
    func historyPaginationLimits() {
        #expect(MessageHistoryPaginationLogic.initialLimit == 20)
        #expect(MessageHistoryPaginationLogic.nextLimit(after: 20) == 40)
        #expect(MessageHistoryPaginationLogic.nextLimit(after: 40) == 60)
    }

    @Test("A full page indicates that older history may exist")
    func fullHistoryPageHasMore() {
        #expect(MessageHistoryPaginationLogic.hasMore(receivedCount: 20, requestedLimit: 20))
        #expect(!MessageHistoryPaginationLogic.hasMore(receivedCount: 19, requestedLimit: 20))
    }


    @Test("Append adds message")
    func appendMessage() {
        let store = MessageStore()
        let msg = Message(role: .user, content: "Hello")
        store.append(msg)
        #expect(store.messages.count == 1)
        #expect(store.messages[0].content == "Hello")
    }

    @Test("Append multiple messages preserves order")
    func appendOrder() {
        let store = MessageStore()
        store.append(Message(role: .user, content: "A"))
        store.append(Message(role: .assistant, content: "B"))
        store.append(Message(role: .user, content: "C"))
        #expect(store.messages.count == 3)
        #expect(store.messages[0].content == "A")
        #expect(store.messages[1].content == "B")
        #expect(store.messages[2].content == "C")
    }

    @Test("Update mutates message by id")
    func updateMessage() {
        let store = MessageStore()
        let id = UUID().uuidString
        store.append(Message(id: id, role: .assistant, content: ""))
        store.update(id: id) { msg in
            msg.content = "Updated"
        }
        #expect(store.messages[0].content == "Updated")
    }

    @Test("Update nonexistent id does not crash")
    func updateNonexistent() {
        let store = MessageStore()
        store.append(Message(role: .user, content: "Hello"))
        store.update(id: "nonexistent") { msg in
            msg.content = "Changed"
        }
        #expect(store.messages[0].content == "Hello")
    }

    @Test("SetFinished marks message as finished")
    func setFinished() {
        let store = MessageStore()
        let id = UUID().uuidString
        store.append(Message(id: id, role: .assistant, content: "Hi", isStreaming: true))
        store.setFinished(id: id)
        #expect(store.messages[0].isFinished == true)
        #expect(store.messages[0].isStreaming == false)
    }

    @Test("Prune removes oldest when over maxVisible")
    func pruneOldest() {
        let store = MessageStore(maxVisible: 5, pruneBuffer: 0)
        for i in 0..<10 {
            store.append(Message(role: .user, content: "Msg \(i)"))
        }
        #expect(store.messages.count == 5)
        #expect(store.messages[0].content == "Msg 5")
        #expect(store.messages[4].content == "Msg 9")
    }

    @Test("Prune keeps all when under maxVisible")
    func pruneNone() {
        let store = MessageStore(maxVisible: 100)
        for i in 0..<5 {
            store.append(Message(role: .user, content: "Msg \(i)"))
        }
        #expect(store.messages.count == 5)
    }

    @Test("Dynamic unload keeps upward paging reachable and defers while reading older history")
    func pruneUnloadsHeadKeepsEarlierPages() {
        let store = MessageStore(maxVisible: 5, pruneBuffer: 0)
        for i in 0..<10 {
            store.append(Message(role: .user, content: "Msg \(i)"))
        }

        // F79: the dropped head must stay reachable through upward pagination.
        #expect(store.hasMoreMessages == true)

        // While the reader is scrolling older history the feed must not
        // shift under the cursor.
        store.isPinnedToBottom = false
        store.append(Message(role: .user, content: "unpinned append"))
        #expect(store.messages.count == 6)

        // Back at the bottom the deferred prune trims the window again.
        store.isPinnedToBottom = true
        store.append(Message(role: .user, content: "pinned append"))
        #expect(store.messages.count == 5)
        #expect(store.messages[0].content == "Msg 7")
        #expect(store.hasMoreMessages == true)
    }

    @Test("Current session ID is tracked")
    func sessionTracking() {
        let store = MessageStore()
        #expect(store.currentSessionID == nil)
        store.currentSessionID = "ses_123"
        #expect(store.currentSessionID == "ses_123")
    }

    @Test("Clear removes all messages")
    func clearMessages() {
        let store = MessageStore()
        store.append(Message(role: .user, content: "A"))
        store.append(Message(role: .assistant, content: "B"))
        store.clear()
        #expect(store.messages.isEmpty)
    }

    @Test("Update reasoning on message")
    func updateReasoning() {
        let store = MessageStore()
        let id = UUID().uuidString
        store.append(Message(id: id, role: .assistant, content: "Hello"))
        store.update(id: id) { msg in
            msg.reasoning = "Thinking about the answer"
        }
        #expect(store.messages[0].reasoning == "Thinking about the answer")
    }

    @Test("Append part to message")
    func appendPart() {
        let store = MessageStore()
        let id = UUID().uuidString
        store.append(Message(id: id, role: .assistant, content: "Hi"))
        store.update(id: id) { msg in
            msg.parts.append(.toolCall(name: "bash", args: "ls", result: nil, callID: nil))
        }
        #expect(store.messages[0].parts.count == 1)
        if case .toolCall(let name, _, _, _) = store.messages[0].parts[0] {
            #expect(name == "bash")
        } else {
            Issue.record("Expected toolCall part")
        }
    }

    @Test("Message from server response uses stable server id")
    func messageFromServerUsesServerID() throws {
        let serverMsg = try makeServerMessage(id: "msg_abc", role: "user", text: "Hello")
        let message = MessageStore.message(from: serverMsg)
        #expect(message.id == "msg_abc")
        #expect(message.role == .user)
        #expect(message.content == "Hello")
    }

    @Test("Merge older messages prepends only missing server ids")
    @MainActor
    func mergeOlderPrependsMissing() throws {
        let store = MessageStore(maxVisible: 100)
        store.append(Message(id: "msg_2", role: .user, content: "B"))
        store.append(Message(id: "msg_3", role: .assistant, content: "C"))

        let serverMessages = try [
            makeServerMessage(id: "msg_1", role: "user", text: "A"),
            makeServerMessage(id: "msg_2", role: "user", text: "B"),
            makeServerMessage(id: "msg_3", role: "assistant", text: "C"),
        ]

        let added = store.mergeOlderMessages(from: serverMessages)
        #expect(added == true)
        #expect(store.messages.count == 3)
        #expect(store.messages[0].id == "msg_1")
        #expect(store.messages[1].id == "msg_2")
        #expect(store.messages[2].id == "msg_3")
    }

    @Test("Second merge with same server messages does not duplicate")
    @MainActor
    func mergeOlderDoesNotDuplicate() throws {
        let store = MessageStore()
        store.append(Message(id: "msg_1", role: .user, content: "A"))

        let serverMessages = try [
            makeServerMessage(id: "msg_1", role: "user", text: "A"),
        ]

        #expect(store.mergeOlderMessages(from: serverMessages) == false)
        #expect(store.messages.count == 1)
        #expect(store.hasMoreMessages == false)

        #expect(store.mergeOlderMessages(from: serverMessages) == false)
        #expect(store.messages.count == 1)
    }

    @Test("Merge older messages does not prune prepended history")
    @MainActor
    func mergeOlderDoesNotPrune() throws {
        let store = MessageStore(maxVisible: 5)
        for i in 5..<10 {
            store.append(Message(id: "msg_\(i)", role: .user, content: "Msg \(i)"))
        }
        #expect(store.messages.count == 5)
        #expect(store.messages[0].id == "msg_5")

        let serverMessages = try (0..<10).map { i in
            try makeServerMessage(id: "msg_\(i)", role: "user", text: "Msg \(i)")
        }

        #expect(store.mergeOlderMessages(from: serverMessages) == true)
        #expect(store.messages.count == 10)
        #expect(store.messages[0].id == "msg_0")
        #expect(store.hasMoreMessages == false)
    }

    private func makeServerMessage(id: String, role: String, text: String) throws -> MimoMessageResponse {
        let json = """
        {"info":{"id":"\(id)","role":"\(role)"},"parts":[{"type":"text","text":"\(text)"}]}
        """
        return try JSONDecoder().decode(MimoMessageResponse.self, from: Data(json.utf8))
    }

    @Test("Message from server response restores image parts for user messages")
    func messageFromServerRestoresImages() throws {
        let json = """
        {"info":{"id":"msg_img","role":"user"},"parts":[{"type":"image","mediaType":"image/png","data":"aGVsbG8="}]}
        """
        let serverMsg = try JSONDecoder().decode(MimoMessageResponse.self, from: Data(json.utf8))
        let message = MessageStore.message(from: serverMsg)
        #expect(message.attachedImages?.count == 1)
        #expect(message.attachedImages?[0].base64 == "aGVsbG8=")
        #expect(message.parts.contains { part in
            if case .image(let base64, let mime) = part {
                return base64 == "aGVsbG8=" && mime == "image/png"
            }
            return false
        })
    }
}
