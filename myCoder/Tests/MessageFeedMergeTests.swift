import Testing
import Foundation
@testable import myCoder

@Suite("Message Feed Merge")
struct MessageFeedMergeTests {

    @Test("Refreshing the feed appends only new messages, old ones stay in place")
    @MainActor
    func appendsOnlyNewTail() throws {
        let store = MessageStore()
        store.append(Message(id: "msg_1", role: .user, content: "A"))
        store.append(Message(id: "msg_2", role: .assistant, content: "B"))

        let refreshed = try [
            makeServerMessage(id: "msg_1", role: "user", text: "A"),
            makeServerMessage(id: "msg_2", role: "assistant", text: "B"),
            makeServerMessage(id: "msg_3", role: "assistant", text: "C"),
        ]

        let appended = store.mergeLatestMessages(from: refreshed)
        #expect(appended == 1)
        #expect(store.messages.map(\.id) == ["msg_1", "msg_2", "msg_3"])
    }

    @Test("Repeated refresh with identical payload does not touch existing rows")
    @MainActor
    func unchangedMessagesUntouched() throws {
        let store = MessageStore()
        let refreshed = try [makeServerMessage(id: "msg_1", role: "user", text: "A")]
        _ = store.mergeLatestMessages(from: refreshed)

        // Local-only state attached after the first sync must survive re-syncs.
        store.update(id: "msg_1") { $0.tokensAdded = 42 }

        let appended = store.mergeLatestMessages(from: refreshed)
        #expect(appended == 0)
        #expect(store.messages.count == 1)
        #expect(store.messages[0].tokensAdded == 42)
    }

    @Test("Messages whose content changed are updated in place")
    @MainActor
    func changedMessagesUpdatedInPlace() throws {
        let store = MessageStore()
        store.append(Message(id: "msg_1", role: .assistant, content: "partial"))

        let refreshed = try [makeServerMessage(id: "msg_1", role: "assistant", text: "partial + more")]
        _ = store.mergeLatestMessages(from: refreshed)

        #expect(store.messages.count == 1)
        #expect(store.messages[0].content == "partial + more")
    }

    @Test("Merging into an empty store appends everything")
    @MainActor
    func emptyStoreAppendsAll() throws {
        let store = MessageStore()
        let refreshed = try [
            makeServerMessage(id: "msg_1", role: "user", text: "A"),
            makeServerMessage(id: "msg_2", role: "assistant", text: "B"),
        ]
        let appended = store.mergeLatestMessages(from: refreshed)
        #expect(appended == 2)
        #expect(store.messages.count == 2)
    }

    @Test("Reloading the same session must not clear the feed first")
    func sameSessionReloadDoesNotClear() throws {
        let source = try sourceText("myCoder/Sources/Views/ChatPanelView.swift")
        #expect(source.contains("mergeLatestMessages"))
        // clear() must be conditional on session change, not run unconditionally before every load
        #expect(!source.contains("canLoadOlderMessages = false\n        messageStore.clear()"))
    }

    private func makeServerMessage(id: String, role: String, text: String) throws -> MimoMessageResponse {
        let json = """
        {"info":{"id":"\(id)","role":"\(role)"},"parts":[{"type":"text","text":"\(text)"}]}
        """
        return try JSONDecoder().decode(MimoMessageResponse.self, from: Data(json.utf8))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try RepoRoot.sourceText(relativePath)
    }
}
