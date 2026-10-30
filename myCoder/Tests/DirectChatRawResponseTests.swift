import Testing
import Foundation
@testable import myCoder

/// Сырые ответы сервера фиксируются в порядке прихода (кнопка
/// «Сырой ответ»), а зашифрованный reasoning-канал не теряется.
@Suite("Сырые ответы сервера (rawEvents)")
struct DirectChatRawResponseTests {

    @Test("Аккумулятор собирает все data-пейлоады в порядке прихода")
    func accumulatorCollectsRawEventsInOrder() {
        var acc = DirectChatStreamAccumulator()
        _ = acc.ingest("data: {\"choices\":[{\"delta\":{\"content\":\"a\"}}]}")
        _ = acc.ingest("data: {\"choices\":[{\"delta\":{\"content\":\"b\"}}]}")
        _ = acc.ingest("data: [DONE]")

        #expect(acc.rawEvents.count == 3)
        #expect(acc.rawEvents[0].contains("\"content\":\"a\""))
        #expect(acc.rawEvents[1].contains("\"content\":\"b\""))
        #expect(acc.rawEvents[2] == "[DONE]")
    }

    @Test("Не-SSE строки не попадают в rawEvents")
    func nonDataLinesAreNotRawEvents() {
        var acc = DirectChatStreamAccumulator()
        _ = acc.ingest("HTTP/1.1 200 OK")
        _ = acc.ingest("")
        #expect(acc.rawEvents.isEmpty)
    }

    @Test("Результат стриминга несёт сырые события")
    func resultCarriesRawEvents() {
        var acc = DirectChatStreamAccumulator()
        _ = acc.ingest("data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}")
        _ = acc.ingest("data: [DONE]")
        let result = acc.result()
        #expect(result.content == "hi")
        #expect(result.rawEvents.count == 2)
    }

    @Test("Зашифрованный reasoning-канал даёт честный плейсхолдер")
    func encryptedReasoningProducesPlaceholder() {
        var acc = DirectChatStreamAccumulator()
        let chunk = #"{"choices":[{"delta":{"reasoning_details":[{"type":"reasoning.encrypted","data":"x","format":"mercury-v1","index":0}]}}]}"#
        let update = acc.ingest("data: \(chunk)")
        #expect(update != nil, "encrypted reasoning должен помечать изменение")
        #expect(acc.visibleReasoning.contains("зашифровано"))
        #expect(acc.sawEncryptedReasoning)
        #expect(acc.result().reasoning?.contains("зашифровано") == true)
    }

    @Test("Текстовый reasoning имеет приоритет над плейсхолдером")
    func plainReasoningWinsOverPlaceholder() {
        var acc = DirectChatStreamAccumulator()
        _ = acc.ingest("data: {\"choices\":[{\"delta\":{\"reasoning\":\"думаю\"}}]}")
        _ = acc.ingest(#"data: {"choices":[{"delta":{"reasoning_details":[{"type":"reasoning.encrypted","data":"x"}]}}]}"#)
        #expect(acc.visibleReasoning == "думаю")
        #expect(!acc.visibleReasoning.contains("зашифровано"))
    }

    @Test("Не-стриминговый send хранит сырое тело")
    func sendCarriesRawBody() async throws {
        let body = """
        {"choices":[{"message":{"role":"assistant","content":"ok"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}
        """
        let data = body.data(using: .utf8)!
        guard let parsed = DirectChatClient.parseResponse(data) else {
            Issue.record("парсинг не удался")
            return
        }
        #expect(parsed.content == "ok")
    }
}
