import Testing
import Foundation
@testable import myCoder

@Suite("Reasoning blocks render in arrival order")
struct ReasoningSegmentsTests {

    @Test("Reasoning parts become one spoiler per iteration, in order")
    func partsPreserveOrder() {
        let message = Message(
            id: "m1",
            role: .assistant,
            content: "Final answer",
            parts: [
                .reasoning("First iteration thinking"),
                .toolCall(name: "read_file", args: "path: a.md", result: "ok", callID: "c1"),
                .reasoning("Second iteration thinking"),
                .text("Final answer")
            ]
        )
        let segments: [String] = message.parts.compactMap { part in
            if case .reasoning(let text) = part { return text }
            return nil
        }
        #expect(segments == ["First iteration thinking", "Second iteration thinking"])
    }

    @Test("Legacy messages without reasoning parts fall back to one block")
    func legacyFallback() {
        let message = Message(
            id: "m2",
            role: .assistant,
            content: "Answer",
            reasoning: "Merged legacy reasoning"
        )
        let fromParts = message.parts.compactMap { part -> String? in
            if case .reasoning(let text) = part, !text.isEmpty { return text }
            return nil
        }
        #expect(fromParts.isEmpty)
        #expect(message.reasoning == "Merged legacy reasoning")
    }

    @Test("ThinkingSpoilerView collapses only when an answer is visible")
    func streamingFlag() {
        let streamingMessage = Message(id: "m3", role: .assistant, content: "", isStreaming: true, parts: [.reasoning("live")])
        let stillThinking = !MessageDisplayLogic.hasVisibleAnswer(streamingMessage)
        #expect(stillThinking)

        let answeredMessage = Message(id: "m4", role: .assistant, content: "done", isStreaming: true, parts: [.reasoning("done thinking")])
        #expect(!(!MessageDisplayLogic.hasVisibleAnswer(answeredMessage)))
    }
}
