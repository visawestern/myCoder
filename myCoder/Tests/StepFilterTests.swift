import Testing
import Foundation
@testable import myCoder

@Suite("Step Filtering in Messages")
struct StepFilterTests {

    @Test("Message parts contain stepStart and stepFinish")
    func messageCanContainStepParts() {
        var msg = Message(role: .assistant, content: "Hello")
        msg.parts = [.stepStart, .text("Response"), .stepFinish]
        let stepParts = msg.parts.filter { part in
            if case .stepStart = part { return true }
            if case .stepFinish = part { return true }
            return false
        }
        #expect(stepParts.count == 2)
    }

    @Test("Chat display hides execution step markers")
    func chatDisplayPartsHideSteps() {
        let parts: [MessagePartContent] = [.stepStart, .text("Response text"), .stepFinish]
        let displayable = MessageDisplayLogic.chatDisplayParts(parts)
        #expect(displayable.count == 1)
        if case .text(let value) = displayable[0] {
            #expect(value == "Response text")
        } else {
            Issue.record("Expected text part")
        }
    }

    @Test("Filtering step parts leaves only text and tool parts")
    func filterStepPartsLeavesContent() {
        let parts: [MessagePartContent] = [.stepStart, .text("Response text"), .toolCall(name: "read", args: "{}", result: nil, callID: nil), .stepFinish]
        let displayableParts = MessageDisplayLogic.chatDisplayParts(parts)
        #expect(displayableParts.count == 2)
        if case .text(let t) = displayableParts[0] {
            #expect(t == "Response text")
        } else {
            Issue.record("Expected text part")
        }
        if case .toolCall(let name, _, _, _) = displayableParts[1] {
            #expect(name == "read")
        } else {
            Issue.record("Expected toolCall part")
        }
    }

    @Test("Empty parts list after filtering step parts is empty")
    func emptyAfterFilteringSteps() {
        let parts: [MessagePartContent] = [.stepStart, .stepFinish]
        let displayable = parts.filter { part in
            if case .stepStart = part { return false }
            if case .stepFinish = part { return false }
            return true
        }
        #expect(displayable.isEmpty)
    }

    @Test("Step parts do not contribute to message text extraction")
    func stepPartsNotInText() {
        var msg = Message(role: .assistant, content: "")
        msg.parts = [.stepStart, .text("Actual response"), .stepFinish]
        let texts: [String] = msg.parts.compactMap { part in
            if case .text(let t) = part, !t.isEmpty { return t }
            return nil
        }
        #expect(texts.count == 1)
        #expect(texts[0] == "Actual response")
    }
}
