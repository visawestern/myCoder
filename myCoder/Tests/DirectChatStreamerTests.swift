import Testing
import Foundation
@testable import myCoder

@Suite("Direct chat streaming")
struct DirectChatStreamerTests {

    @Test("Text deltas accumulate in order")
    func textDeltasAccumulate() {
        var accumulator = DirectChatStreamAccumulator()
        _ = accumulator.ingest(#"data: {"choices":[{"delta":{"content":"При"}}]}"#)
        _ = accumulator.ingest(#"data: {"choices":[{"delta":{"content":"вет"}}]}"#)

        #expect(accumulator.content == "Привет")
    }

    @Test("Reasoning deltas are kept apart from the answer")
    func reasoningStaysSeparate() {
        var accumulator = DirectChatStreamAccumulator()
        _ = accumulator.ingest(#"data: {"choices":[{"delta":{"reasoning_content":"думаю "}}]}"#)
        _ = accumulator.ingest(#"data: {"choices":[{"delta":{"reasoning_content":"дальше"}}]}"#)
        _ = accumulator.ingest(#"data: {"choices":[{"delta":{"content":"Ответ"}}]}"#)

        #expect(accumulator.reasoning == "думаю дальше")
        #expect(accumulator.content == "Ответ")
    }

    @Test("[DONE] closes the stream and still reports the collected text")
    func doneMarker() {
        var accumulator = DirectChatStreamAccumulator()
        _ = accumulator.ingest(#"data: {"choices":[{"delta":{"content":"Готово"}}]}"#)
        let update = accumulator.ingest("data: [DONE]")

        #expect(update?.content == "Готово")
    }

    @Test("The usage block of the final event is captured")
    func usageCapture() {
        var accumulator = DirectChatStreamAccumulator()
        _ = accumulator.ingest(#"data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":5}}"#)

        #expect(accumulator.usage?.promptTokens == 12)
        #expect(accumulator.usage?.completionTokens == 5)
    }

    @Test("Cumulative message chunks replace text instead of doubling it")
    func cumulativeChunksDoNotDuplicate() {
        var accumulator = DirectChatStreamAccumulator()
        _ = accumulator.ingest(#"data: {"choices":[{"message":{"content":"При"}}]}"#)
        _ = accumulator.ingest(#"data: {"choices":[{"message":{"content":"Привет"}}]}"#)

        #expect(accumulator.content == "Привет")
    }

    @Test("Array-shaped content blocks are joined")
    func arrayContentBlocks() {
        var accumulator = DirectChatStreamAccumulator()
        _ = accumulator.ingest(#"data: {"choices":[{"delta":{"content":[{"type":"text","text":"раз "},{"type":"text","text":"два"}]}}]}"#)

        #expect(accumulator.content == "раз два")
    }

    @Test("A provider that ignored stream:true is parsed as a normal response")
    func nonStreamingFallback() {
        var accumulator = DirectChatStreamAccumulator()
        _ = accumulator.ingest(#"{"choices":[{"message":{"content":"Обычный ответ"}}]}"#)

        #expect(accumulator.sawDataLine == false)
        #expect(accumulator.fallbackResult(contextBytes: 0)?.content == "Обычный ответ")
    }

    @Test("An empty stream is reported as empty, not as a valid answer")
    func emptyStream() {
        var accumulator = DirectChatStreamAccumulator()
        _ = accumulator.ingest(#"data: {"choices":[{"delta":{"content":""}}]}"#)

        #expect(accumulator.isEmpty)
    }
}
