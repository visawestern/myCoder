import Testing
@testable import myCoder

@Suite("Reasoning display")
struct ReasoningDisplayTests {

    @Test("Deduplicates reasoning stored in both field and parts")
    func deduplicatesReasoningFieldAndParts() {
        let message = Message(
            role: .assistant,
            content: "answer",
            parts: [.reasoning("same thought"), .text("answer")],
            reasoning: "same thought"
        )
        #expect(MessageDisplayLogic.deduplicatedReasoning(message) == "same thought")
    }

    @Test("Folds orphan thinking row into following answer")
    func foldsThinkingIntoAnswer() {
        let thinking = Message(
            role: .assistant,
            content: "",
            parts: [.reasoning("planning")],
            reasoning: "planning",
            isFinished: true
        )
        let answer = Message(
            role: .assistant,
            content: "Done",
            parts: [.text("Done")],
            isFinished: true
        )
        let result = MessageDisplayLogic.messagesForDisplay([thinking, answer])
        #expect(result.count == 1)
        #expect(result[0].content == "Done")
        #expect(result[0].reasoning == "planning")
    }
}
