import Testing
import Foundation
@testable import myCoder

@Suite("Последовательная доставка чанков контекста")
struct ChunkedSendSequencerTests {

    private func chunks(_ count: Int) -> [PromptChunk] {
        (0..<count).map { index in
            PromptChunk(index: index + 1, total: count, text: "chunk \(index + 1)")
        }
    }

    @Test("OpenAI-совместимый маршрут — один запрос")
    func openAICompatibleIsSingleRequest() {
        #expect(ChunkedSendSequencer.strategy(for: .openAICompatible(baseURL: "http://x/v1", apiKey: nil, model: "m")) == .singleRequest)
    }

    @Test("Web/ACP/serve маршруты — последовательные запросы")
    func sequentialRoutes() {
        #expect(ChunkedSendSequencer.strategy(for: .web(configID: "c")) == .sequentialRequests)
        #expect(ChunkedSendSequencer.strategy(for: .acp) == .sequentialRequests)
        #expect(ChunkedSendSequencer.strategy(for: .mimoServe) == .sequentialRequests)
        #expect(ChunkedSendSequencer.strategy(for: .openCodeServe(
            baseURL: "http://x", headers: [:], providerID: "p", model: "m"
        )) == .sequentialRequests)
    }

    @Test("Один чанк уходит как есть")
    func singleChunkUnchanged() {
        let payloads = ChunkedSendSequencer.payloads(for: chunks(1), strategy: .sequentialRequests)
        #expect(payloads == ["chunk 1"])
    }

    @Test("Первый последовательный чанк просит дождаться остальных")
    func firstChunkWaits() {
        let payloads = ChunkedSendSequencer.payloads(for: chunks(3), strategy: .sequentialRequests)
        #expect(payloads.count == 3)
        #expect(payloads[0].contains("часть 1/3"))
        #expect(payloads[0].contains("дожд"))
        #expect(payloads[2].contains("последняя"))
    }

    @Test("В одном запросе пояснений ждать не нужно")
    func singleRequestHasNoWaitingNotes() {
        let payloads = ChunkedSendSequencer.payloads(for: chunks(3), strategy: .singleRequest)
        #expect(payloads == ["chunk 1", "chunk 2", "chunk 3"])
    }

    @Test("Объединённый текст содержит все части")
    func combinedTextHasEverything() {
        let text = ChunkedSendSequencer.combinedText(for: chunks(3), strategy: .singleRequest)
        #expect(text.contains("chunk 1"))
        #expect(text.contains("chunk 2"))
        #expect(text.contains("chunk 3"))
    }
}
