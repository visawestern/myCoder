import Testing
import Foundation
@testable import myCoder

@Suite("Consecutive thinking message merge")
struct ThinkingMergeTests {

    private func thinkingOnly(id: String = UUID().uuidString, reasoning: String = "planning") -> Message {
        Message(
            id: id,
            role: .assistant,
            content: "",
            parts: [.stepStart, .reasoning(reasoning), .stepFinish],
            reasoning: reasoning,
            isFinished: true
        )
    }

    private func textReply(_ text: String) -> Message {
        Message(
            role: .assistant,
            content: text,
            parts: [.text(text)],
            isFinished: true
        )
    }

    @Test("Single thinking-only message stays as one")
    func singleThinkingUnchanged() {
        let input = [thinkingOnly(reasoning: "a")]
        let result = MessageDisplayLogic.messagesForDisplay(input)
        #expect(result.count == 1)
        #expect(result[0].reasoning == "a")
    }

    @Test("Three consecutive thinking-only messages merge into one")
    func mergeThreeThinkingRows() {
        let input = [
            thinkingOnly(id: "t1", reasoning: "step one"),
            thinkingOnly(id: "t2", reasoning: "step two"),
            thinkingOnly(id: "t3", reasoning: "step three"),
        ]
        let result = MessageDisplayLogic.messagesForDisplay(input)
        #expect(result.count == 1)
        #expect(result[0].reasoning.contains("step one"))
        #expect(result[0].reasoning.contains("step two"))
        #expect(result[0].reasoning.contains("step three"))
        #expect(result[0].id == "t3")
    }

    @Test("Thinking group separated by user message does not merge across")
    func userMessageBreaksMerge() {
        let user = Message(role: .user, content: "hello")
        let input = [
            thinkingOnly(id: "a", reasoning: "first"),
            user,
            thinkingOnly(id: "b", reasoning: "second"),
        ]
        let result = MessageDisplayLogic.messagesForDisplay(input)
        #expect(result.count == 3)
        #expect(result[0].reasoning == "first")
        #expect(result[1].role == .user)
        #expect(result[2].reasoning == "second")
    }

    @Test("Thinking group separated by text reply folds into one assistant row")
    func textReplyBreaksMerge() {
        let input = [
            thinkingOnly(reasoning: "think"),
            textReply("Here is the answer"),
            thinkingOnly(reasoning: "more think"),
        ]
        let result = MessageDisplayLogic.messagesForDisplay(input)
        #expect(result.count == 2)
        #expect(result[0].content == "Here is the answer")
        #expect(result[0].reasoning.contains("think"))
        #expect(result[1].reasoning == "more think")
    }

    @Test("Step-only messages with no reasoning are omitted from display")
    func stepOnlyRowsHidden() {
        let stepOnly = Message(
            role: .assistant,
            content: "",
            parts: [.stepStart, .stepFinish],
            isFinished: true
        )
        let result = MessageDisplayLogic.messagesForDisplay([stepOnly, stepOnly, stepOnly])
        #expect(result.isEmpty)
    }

    @Test("Tool call message is never merged with thinking-only neighbor")
    func toolCallBreaksThinkingMerge() {
        let toolMsg = Message(
            role: .assistant,
            content: "",
            parts: [.toolCall(name: "read", args: "{}", result: "ok", callID: nil)],
            isFinished: true
        )
        let input = [thinkingOnly(reasoning: "a"), toolMsg, thinkingOnly(reasoning: "b")]
        let result = MessageDisplayLogic.messagesForDisplay(input)
        #expect(result.count == 3)
        if case .toolCall(let name, _, _, _) = result[1].parts.first {
            #expect(name == "read")
        } else {
            Issue.record("Expected tool call message in the middle")
        }
    }

    @Test("isThinkingOnly returns false for assistant with visible text")
    func textMessageNotThinkingOnly() {
        let msg = textReply("visible")
        #expect(MessageDisplayLogic.isThinkingOnly(msg) == false)
    }
}
