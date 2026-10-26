import Testing
@testable import myCoder

@Suite("Chat copy")
struct ChatCopyLogicTests {

    @Test("Builds transcript from user and assistant messages")
    func buildsTranscript() {
        let messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there", parts: [.text("Hi there")])
        ]

        let transcript = ChatCopyLogic.transcript(from: messages)

        #expect(transcript.contains("User"))
        #expect(transcript.contains("Hello"))
        #expect(transcript.contains("Assistant"))
        #expect(transcript.contains("Hi there"))
    }

    @Test("Skips empty messages")
    func skipsEmpty() {
        let messages = [
            Message(role: .user, content: "Only this"),
            Message(role: .assistant, content: "")
        ]

        let transcript = ChatCopyLogic.transcript(from: messages)

        #expect(transcript.contains("Only this"))
        #expect(transcript.contains("Assistant") == false)
    }

    @Test("empty transcript reports no copy instead of success")
    func emptyTranscriptIsNotCopied() {
        #expect(ChatCopyLogic.result(from: []) == .empty)
    }

    @Test("visible transcript reports copied content")
    func visibleTranscriptIsCopied() {
        let message = Message(id: "message-1", role: .user, content: "Hello")
        #expect(ChatCopyLogic.result(from: [message]) == .copied("User:\nHello"))
    }
}
