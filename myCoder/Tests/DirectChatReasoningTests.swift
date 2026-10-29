import Testing
import Foundation
@testable import myCoder

/// The direct (OpenAI-compatible) route used to drop the provider's thinking
/// channel entirely, so the reasoning spoiler stayed empty even when the model
/// returned `reasoning_content` / `thinking`.
@Suite("Рассуждения модели в прямом маршруте")
struct DirectChatReasoningTests {

    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    @Test("OpenAI-совместимый ответ: reasoning_content попадает в результат")
    func openAIReasoningContentIsParsed() {
        let data = json("""
        {"choices":[{"index":0,"message":{
          "role":"assistant",
          "content":"Ответ",
          "reasoning_content":"Сначала проверяю UserStore."
        }}]}
        """)
        let result = DirectChatClient.parseResponse(data)
        #expect(result?.content == "Ответ")
        #expect(result?.reasoning == "Сначала проверяю UserStore.")
    }

    @Test("OpenRouter-style reasoning и Ollama thinking читаются")
    func alternativeSpellingsAreParsed() {
        let openRouter = json("""
        {"choices":[{"message":{"role":"assistant","content":"ok","reasoning":"думаю"}}]}
        """)
        #expect(DirectChatClient.parseResponse(openRouter)?.reasoning == "думаю")

        let ollama = json("""
        {"message":{"role":"assistant","content":"ok","thinking":"размышляю"},"done":true}
        """)
        #expect(DirectChatClient.parseResponse(ollama)?.reasoning == "размышляю")
    }

    @Test("Массив блоков рассуждений склеивается")
    func blockArrayIsJoined() {
        let data = json("""
        {"choices":[{"message":{"role":"assistant","content":"ok",
          "reasoning":[{"type":"text","text":"шаг 1"},{"type":"text","text":"шаг 2"}]}}]}
        """)
        #expect(DirectChatClient.parseResponse(data)?.reasoning == "шаг 1\n\nшаг 2")
    }

    @Test("Без канала рассуждений результат остаётся nil, ответ не ломается")
    func missingReasoningIsNil() {
        let data = json("""
        {"choices":[{"message":{"role":"assistant","content":"просто ответ"}}]}
        """)
        let result = DirectChatClient.parseResponse(data)
        #expect(result?.content == "просто ответ")
        #expect(result?.reasoning == nil)
    }

    @Test("Повторяющиеся блоки между итерациями не дублируются")
    func mergedReasoningDropsRepeats() {
        let merged = DirectChatClient.mergedReasoning(["блок", "блок", "второй", "", "  "])
        #expect(merged == "блок\n\nвторой")
        #expect(DirectChatClient.mergedReasoning([]) == nil)
    }

    @Test("send() возвращает рассуждения вместе с текстом")
    func sendCarriesReasoning() async throws {
        let body = json("""
        {"choices":[{"message":{"role":"assistant","content":"готово","reasoning_content":"план"}}]}
        """)
        let transport = MockDirectChatTransport(response: (200, body))
        let result = try await DirectChatClient.send(
            baseURL: "http://x/", apiKey: nil, model: "m",
            messages: [DirectChatMessage(role: "user", content: "hi")],
            transport: transport
        )
        #expect(result.reasoning == "план")
    }
}
