import Testing
import Foundation
@testable import myCoder

@Suite("Компакция истории чата")
struct HistoryCompactifierTests {

    private func turn(_ role: String, _ content: String) -> ChatHistoryBuilder.Turn {
        ChatHistoryBuilder.Turn(role: role, content: content, isFinished: true)
    }

    @Test("Сжатая история — цепочка тезисов, не сырой текст")
    func compactProducesThesisChain() {
        let turns = [
            turn("user", "Исправь баг в UserStore.swift"),
            turn("assistant", "Сделано: поправил метод loadUser, добавил тест.")
        ]
        let body = HistoryCompactifier.compact(turns)
        #expect(body.contains("История чата (сжатая"))
        #expect(body.contains("1. [Пользователь]"))
        #expect(body.contains("2. [Ассистент]"))
        #expect(body.contains("[сделано]"))
        // Raw dump must not leak verbatim.
        #expect(!body.contains("[Пользователь] Исправь баг"))
    }

    @Test("Статус делается по версии чата")
    func statusClassification() {
        #expect(HistoryCompactifier.classify("Сделано: добавил тест", role: "assistant") == .done)
        #expect(HistoryCompactifier.classify("Нужно ещё поправить парсер", role: "assistant") == .notDone)
        #expect(HistoryCompactifier.classify("А что будет с кэшем?", role: "assistant") == .open)
        // Empty/ambiguous assistant turn without completion verbs → not done.
        #expect(HistoryCompactifier.classify("Посмотрел код", role: "assistant") == .notDone)
    }

    @Test("Разбиение на предложения не режет пути")
    func splitKeepsPathsTogether() {
        let sentences = HistoryCompactifier.splitSentences("Открой file.swift. Поправь v1.2. Готово!")
        #expect(sentences == ["Открой file.swift.", "Поправь v1.2.", "Готово!"])
    }

    @Test("Ключевые тезисы распознаются")
    func keyThesisDetection() {
        #expect(HistoryCompactifier.isKeyThesis("исправил файл UserStore.swift"))
        #expect(HistoryCompactifier.isKeyThesis("решили взять gpt-4o"))
        #expect(!HistoryCompactifier.isKeyThesis("да"))
    }

    @Test("Пустая история даёт пустую секцию")
    func emptyHistory() {
        #expect(HistoryCompactifier.compact([]) == "")
    }
}

@Suite("Новые дефолты контекста")
struct ContextDefaultsTests {

    @Test("Бюджет чтения файлов — 128 000 токенов")
    func defaultBudgetIs128k() {
        #expect(TurnContextCompiler.defaultBudgetTokens == 128_000)
    }

    @Test("Каталог скиллов вмещает весь установленный набор (≥106)")
    func skillCatalogCapSufficient() {
        #expect(TurnEvidence.maxSkillCatalog >= 106)
        #expect(LocalPlannerPromptBuilder.maxSkillCatalogItems >= 106)
    }
}
