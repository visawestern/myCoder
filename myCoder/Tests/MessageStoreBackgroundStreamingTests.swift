import Testing
import Foundation
@testable import myCoder

/// The message store holds one feed per chat so a model turn can keep writing
/// while the user reads another conversation.
@Suite("MessageStore background streaming")
struct MessageStoreBackgroundStreamingTests {

    @Test("A background append lands in its own chat and not in the visible one")
    func appendToBackgroundSession() {
        let store = MessageStore()
        store.currentSessionID = "ses_visible"
        store.append(Message(role: .user, content: "visible turn"))

        store.append(
            Message(id: "bg-assistant", role: .assistant, content: "streaming…", isStreaming: true),
            to: "ses_background"
        )

        #expect(store.messages.map(\.content) == ["visible turn"])
        #expect(store.messages(in: "ses_background").map(\.id) == ["bg-assistant"])
    }

    @Test("Switching chats shows the other feed without dropping the first")
    func switchingChatsKeepsEveryFeed() {
        let store = MessageStore()
        store.currentSessionID = "ses_a"
        store.append(Message(id: "a1", role: .user, content: "A"))
        store.currentSessionID = "ses_b"
        store.append(Message(id: "b1", role: .user, content: "B"))

        #expect(store.messages.map(\.id) == ["b1"])
        store.currentSessionID = "ses_a"
        #expect(store.messages.map(\.id) == ["a1"])
        #expect(store.messages(in: "ses_b").map(\.id) == ["b1"])
    }

    @Test("A streaming message marks its session as active until it finishes")
    func streamingSessionIDsFollowTheTurn() {
        let store = MessageStore()
        let streaming = Message(id: "live", role: .assistant, content: "", isStreaming: true)
        store.append(streaming, to: "ses_live")

        #expect(store.streamingSessionIDs == ["ses_live"])

        store.setFinished(id: "live")

        #expect(store.streamingSessionIDs.isEmpty)
        #expect(store.message(id: "live")?.isFinished == true)
    }

    @Test("A chunk updates the message in a chat the user is not looking at")
    func updateByIDWorksAcrossFeeds() {
        let store = MessageStore()
        store.currentSessionID = "ses_visible"
        store.append(Message(role: .user, content: "reading this"))
        store.append(
            Message(id: "bg", role: .assistant, content: "", isStreaming: true),
            to: "ses_background"
        )

        store.update(id: "bg") { message in
            message.content = "background chunk"
        }

        #expect(store.messages.map(\.content) == ["reading this"])
        #expect(store.messages(in: "ses_background").first?.content == "background chunk")
    }

    @Test("A message resolves to the session that owns it")
    func owningSessionResolution() {
        let store = MessageStore()
        store.append(Message(id: "owned", role: .user, content: "hi"), to: "ses_owner")

        #expect(store.sessionID(owningMessageID: "owned") == "ses_owner")
        #expect(store.sessionID(owningMessageID: "missing") == nil)
    }

    @Test("Detaching keeps background feeds and their streaming state")
    func detachPreservesBackgroundTurns() {
        let store = MessageStore()
        store.currentSessionID = "ses_background"
        store.append(
            Message(id: "bg", role: .assistant, content: "", isStreaming: true)
        )

        store.detach()

        #expect(store.currentSessionID == nil)
        #expect(store.messages.isEmpty)
        #expect(store.messages(in: "ses_background").map(\.id) == ["bg"])
        #expect(store.streamingSessionIDs == ["ses_background"])
        #expect(store.hasLoadedMessages(sessionID: "ses_background"))
    }

    @Test("A chat is only considered cached when it has a loaded feed")
    func loadedMessagesDecision() {
        let store = MessageStore()
        #expect(store.hasLoadedMessages(sessionID: "ses_empty") == false)

        store.append(Message(role: .user, content: "hello"), to: "ses_empty")

        #expect(store.hasLoadedMessages(sessionID: "ses_empty"))
    }
}
