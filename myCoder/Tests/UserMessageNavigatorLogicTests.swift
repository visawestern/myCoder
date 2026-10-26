import Foundation
import Testing
@testable import myCoder

struct UserMessageNavigatorLogicTests {

    @Test("Only user messages with content are navigable")
    func filtersToUserMessages() {
        let messages = [
            Message(role: .assistant, content: "answer"),
            Message(role: .user, content: "first question"),
            Message(role: .user, content: "   "),
            Message(role: .user, content: "second question")
        ]

        let navigable = UserMessageNavigatorLogic.userMessages(messages)

        #expect(navigable.map(\.content) == ["first question", "second question"])
    }

    @Test("Attachment-only user messages stay navigable")
    func keepsAttachmentOnlyMessages() {
        let message = Message(
            role: .user,
            content: "",
            files: [FileInfo(name: "Notes.swift", type: .swift)]
        )

        let navigable = UserMessageNavigatorLogic.userMessages([message])

        #expect(navigable.count == 1)
        #expect(UserMessageNavigatorLogic.preview(for: message) == "Notes.swift")
    }

    @Test("Preview collapses newlines and repeated whitespace")
    func normalizesPreview() {
        let message = Message(role: .user, content: "  First line\n\nSecond   line  ")

        #expect(UserMessageNavigatorLogic.preview(for: message) == "First line Second line")
    }

    @Test("Preview truncates to one hundred characters")
    func truncatesPreview() {
        let message = Message(role: .user, content: String(repeating: "a", count: 140))

        let preview = UserMessageNavigatorLogic.preview(for: message)

        #expect(preview == String(repeating: "a", count: 100) + "…")
        #expect(preview.count == 101)
    }

    @Test("Preview exactly at the limit is not truncated")
    func keepsExactLimit() {
        let message = Message(role: .user, content: String(repeating: "b", count: 100))

        #expect(UserMessageNavigatorLogic.preview(for: message) == String(repeating: "b", count: 100))
    }

    @Test("Preview trims whitespace exposed by truncation")
    func trimsTrailingWhitespaceAfterTruncation() {
        let message = Message(role: .user, content: String(repeating: "a", count: 99) + "   tail")

        let preview = UserMessageNavigatorLogic.preview(for: message)

        #expect(preview == String(repeating: "a", count: 99) + "…")
    }

    @Test("Button title uses a one-based index")
    func buttonTitle() {
        #expect(UserMessageNavigatorLogic.buttonTitle(index: 0) == "1")
        #expect(UserMessageNavigatorLogic.buttonTitle(index: 11) == "12")
    }

    @Test("Stepping moves toward the middle of the list")
    func stepping() {
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 0, direction: .down, messageCount: 3) == 1)
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 2, direction: .up, messageCount: 3) == 1)
    }

    @Test("Stepping returns nil at the edges or on an empty list")
    func steppingEdges() {
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 0, direction: .up, messageCount: 3) == nil)
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 2, direction: .down, messageCount: 3) == nil)
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 0, direction: .down, messageCount: 0) == nil)
    }

    @Test("Current message is the one covering the viewport middle line")
    func resolvesCurrentInsideBand() {
        let a = Message(role: .user, content: "a")
        let b = Message(role: .user, content: "b")
        let frames = [a.id: CGRect(x: 0, y: 0, width: 100, height: 50),
                      b.id: CGRect(x: 0, y: 50, width: 100, height: 50)]

        let current = UserMessageNavigatorLogic.currentUserMessageID(
            visibleRect: CGRect(x: 0, y: 20, width: 100, height: 60),
            frames: frames,
            messages: [a, b]
        )

        #expect(current == b.id)
    }

    @Test("Current message falls back to the last message above the viewport")
    func resolvesCurrentAbove() {
        let a = Message(role: .user, content: "a")
        let frames = [a.id: CGRect(x: 0, y: 0, width: 100, height: 50)]

        let current = UserMessageNavigatorLogic.currentUserMessageID(
            visibleRect: CGRect(x: 0, y: 100, width: 100, height: 200),
            frames: frames,
            messages: [a]
        )

        #expect(current == a.id)
    }

    @Test("Current resolution needs frames and a viewport")
    func resolutionGuards() {
        let a = Message(role: .user, content: "a")
        let frames = [a.id: CGRect(x: 0, y: 0, width: 100, height: 50)]

        #expect(UserMessageNavigatorLogic.currentUserMessageID(
            visibleRect: .zero, frames: frames, messages: [a]) == nil)
        #expect(UserMessageNavigatorLogic.currentUserMessageID(
            visibleRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            frames: [:], messages: [a]) == nil)
    }
}
