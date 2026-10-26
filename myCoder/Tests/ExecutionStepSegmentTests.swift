import Testing
@testable import myCoder

@Suite("Execution step segments")
struct ExecutionStepSegmentTests {

    @Test("Groups parts between step markers into segments")
    func groupsStepSegments() {
        let parts: [MessagePartContent] = [
            .stepStart,
            .toolCall(name: "read", args: "{}", result: "ok", callID: nil),
            .stepFinish,
            .text("Answer")
        ]
        let segments = MessageDisplayLogic.groupPartsByExecutionSteps(parts)
        #expect(segments.count == 2)
        #expect(segments[0].stepNumber == 1)
        #expect(segments[0].isComplete)
        #expect(segments[1].stepNumber == 0)
    }

    @Test("Active step segment shows in-progress state")
    func activeStepSegment() {
        let parts: [MessagePartContent] = [
            .stepStart,
            .toolCall(name: "read", args: "{}", result: nil, callID: nil)
        ]
        let segments = MessageDisplayLogic.groupPartsByExecutionSteps(parts)
        #expect(segments.count == 1)
        #expect(segments[0].stepNumber == 1)
        #expect(segments[0].isActive)
        #expect(!segments[0].isComplete)
    }

    @Test("Fold preserves step markers from thinking row")
    func foldPreservesStepMarkers() {
        let thinking = Message(
            role: .assistant,
            content: "",
            parts: [.stepStart, .reasoning("plan"), .stepFinish],
            reasoning: "plan",
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
        #expect(result[0].parts.contains { if case .stepStart = $0 { return true }; return false })
        #expect(result[0].parts.contains { if case .stepFinish = $0 { return true }; return false })
    }
}
