import Testing
import Foundation
@testable import myCoder

/// Стратегия чанковой отправки: выбор по маршруту и упаковка пейлоадов
/// с маркерами «часть 1/…» и «последняя часть …».
@Suite("Чанковая отправка (ChunkedSendSequencer)")
struct ChunkedSendSequencerTests {

    private func chunk(_ i: Int, _ total: Int, _ text: String) -> PromptChunk {
        PromptChunk(index: i, total: total, text: text)
    }

    @Test("OpenAI-совместимые маршруты — один запрос")
    func openAICompatibleUsesSingleRequest() {
        #expect(ChunkedSendSequencer.strategy(for: .openAICompatible(baseURL: "u", apiKey: nil, model: "m")) == .singleRequest)
        #expect(ChunkedSendSequencer.strategy(for: .none) == .singleRequest)
    }

    @Test("Web/ACP/serve маршруты — последовательные запросы")
    func sequentialRoutesUseSequentialRequests() {
        #expect(ChunkedSendSequencer.strategy(for: .web(configID: "w")) == .sequentialRequests)
        #expect(ChunkedSendSequencer.strategy(for: .acp) == .sequentialRequests)
        #expect(ChunkedSendSequencer.strategy(for: .mimoServe) == .sequentialRequests)
        #expect(ChunkedSendSequencer.strategy(for: .openCodeServe(baseURL: "u", headers: [:], providerID: "p", model: "m")) == .sequentialRequests)
    }

    @Test("Пустой список — пустые пейлоады")
    func emptyChunksYieldNoPayloads() {
        #expect(ChunkedSendSequencer.payloads(for: [], strategy: .sequentialRequests).isEmpty)
    }

    @Test("Один чанк — как есть, без маркеров")
    func singleChunkPassthrough() {
        let payloads = ChunkedSendSequencer.payloads(for: [chunk(1, 1, "text")], strategy: .sequentialRequests)
        #expect(payloads == ["text"])
    }

    @Test("Одиночный запрос: все части как отдельные сообщения")
    func singleRequestPassesAllChunks() {
        let payloads = ChunkedSendSequencer.payloads(
            for: [chunk(1, 2, "a"), chunk(2, 2, "b")],
            strategy: .singleRequest
        )
        #expect(payloads == ["a", "b"])
    }

    @Test("Последовательные запросы: первая и последняя часть получают маркеры")
    func sequentialRequestsMarkFirstAndLast() {
        let payloads = ChunkedSendSequencer.payloads(
            for: [chunk(1, 3, "a"), chunk(2, 3, "b"), chunk(3, 3, "c")],
            strategy: .sequentialRequests
        )
        #expect(payloads.count == 3)
        #expect(payloads[0].contains("[часть 1/3"))
        #expect(payloads[1] == "b", "средняя часть без маркера")
        #expect(payloads[2].contains("[последняя часть 3/3"))
    }
}
