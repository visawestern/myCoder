import Testing
import Foundation
@testable import myCoder

/// User complaint 2026-11-07: the "Контекст" button opened an empty window.
/// The sheet content must be derived from the message itself (the stored
/// `.compiledContext` part / `contextSummary`), never from transient view
/// state: a re-created row, a session reload or sheet timing then cannot make
/// a real pack disappear.
@Suite("Окно «Контекст» читает данные из сообщения")
struct MessageContextSheetLogicTests {

    @Test("Собранный контекст показывается целиком и важнее причины")
    func compiledContextWins() {
        let content = MessageContextSheetLogic.content(
            compiledContextText: "## Запрос\nпочини кнопку",
            summary: "Собран точечный контекст: файлов: 2"
        )
        #expect(content.displayText == "## Запрос\nпочини кнопку")
        #expect(content.fallback == "Собран точечный контекст: файлов: 2")
    }

    @Test("Без пакета окно показывает причину, а не пустоту")
    func honestReasonIsShown() {
        let content = MessageContextSheetLogic.content(
            compiledContextText: nil,
            summary: "Первый промпт в чате — контекст не собирался."
        )
        #expect(content.text.isEmpty)
        #expect(content.displayText == "Первый промпт в чате — контекст не собирался.")
    }

    @Test("Пустые оба значения дают честный текст вместо пустого окна")
    func emptyContentIsNeverBlank() {
        let content = MessageContextSheetLogic.content(compiledContextText: nil, summary: nil)
        #expect(!content.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(content.displayText == "Контекст не собран.")
    }

    @Test("Пробелы не считаются собранным контекстом")
    func whitespaceIsNotContext() {
        let content = MessageContextSheetLogic.content(compiledContextText: " \n\t ", summary: "   ")
        #expect(content.text.isEmpty)
        #expect(content.fallback == nil)
        #expect(content.displayText == "Контекст не собран.")
    }

    @Test("После перезагрузки контекст берётся из parts сообщения")
    func readsContextFromMessageParts() {
        // The DB reload restores `.compiledContext` parts but does not restore
        // `contextSummary`. The sheet must still show the real pack.
        let message = Message(
            role: .user,
            content: "вопрос",
            parts: [.text("вопрос"), .compiledContext("## Запрос\nвопрос\n\n### Store.swift:1-2")]
        )
        let content = MessageContextSheetLogic.content(for: message)
        #expect(content.text.contains("Store.swift:1-2"))
        #expect(content.fallback == nil)
        #expect(content.displayText.contains("Store.swift:1-2"))
    }

    @Test("Причина отсутствия пакета берётся из contextSummary")
    func readsSummaryFromMessage() {
        let message = Message(
            role: .user,
            content: "вопрос",
            contextSummary: "Чат без проекта — точечного проектного контекста нет."
        )
        let content = MessageContextSheetLogic.content(for: message)
        #expect(content.text.isEmpty)
        #expect(content.displayText.contains("Чат без проекта"))
    }

    @Test("Несколько частей контекста: берётся первый непустой")
    func firstNonEmptyPartWins() {
        let message = Message(
            role: .user,
            content: "вопрос",
            parts: [.compiledContext(""), .compiledContext("настоящий пакет")]
        )
        #expect(MessageContextSheetLogic.content(for: message).displayText == "настоящий пакет")
    }
}
