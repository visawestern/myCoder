import Testing
import Foundation
@testable import myCoder

/// Навигатор по сообщениям пользователя: фильтрация user-сообщений,
/// превью (обрезка и нормализация пробелов), номера кнопок и шаги
/// перехода.
@MainActor
@Suite("Логика навигатора по сообщениям (UserMessageNavigatorLogic)")
struct UserMessageNavigatorLogicTests {

    private func message(_ id: String, role: MessageRole = .user, content: String = "", files: [FileInfo]? = nil) -> Message {
        Message(id: id, role: role, content: content, files: files)
    }

    @Test("userMessages: только user-сообщения с непустым превью")
    func userMessagesFilter() {
        let messages = [
            message("a", content: "привет"),
            message("b", role: .assistant, content: "ответ"),
            message("c", content: "   "),
            message("d", content: "", files: [FileInfo(name: "file.txt", type: .unknown, path: "/tmp/file.txt")])
        ]
        let users = UserMessageNavigatorLogic.userMessages(messages)
        #expect(users.map(\.id) == ["a", "d"])
        #expect(UserMessageNavigatorLogic.userMessageCount(messages) == 2)
    }

    @Test("Превью обрезается и схлопывает пробелы")
    func previewNormalizesAndTruncates() {
        #expect(UserMessageNavigatorLogic.preview(for: message("1", content: "a  b\nc")) == "a b c")
        let long = String(repeating: "x", count: 200)
        let preview = UserMessageNavigatorLogic.preview(for: message("2", content: long))
        #expect(preview.hasSuffix("…"))
        #expect(preview.count <= 101)
    }

    @Test("Превью использует имена файлов, когда текста нет")
    func previewFallsBackToFiles() {
        let m = message("3", content: "", files: [
            FileInfo(name: "a.txt", type: .unknown, path: "/tmp/a.txt"),
            FileInfo(name: "b.txt", type: .unknown, path: "/tmp/b.txt")
        ])
        #expect(UserMessageNavigatorLogic.preview(for: m) == "a.txt, b.txt")
    }

    @Test("Номера кнопок учитывают offset")
    func buttonTitles() {
        #expect(UserMessageNavigatorLogic.buttonTitle(index: 0) == "1")
        #expect(UserMessageNavigatorLogic.buttonTitle(index: 2, offset: 5) == "8")
    }

    @Test("steppedIndex ходит по списку, останавливаясь на границах")
    func steppedIndexBounds() {
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 0, direction: .up, messageCount: 3) == nil)
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 0, direction: .down, messageCount: 3) == 1)
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 2, direction: .down, messageCount: 3) == nil)
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 2, direction: .up, messageCount: 3) == 1)
        #expect(UserMessageNavigatorLogic.steppedIndex(from: 0, direction: .down, messageCount: 0) == nil)
    }

    /// A character sequence that counts how much of it was actually read.
    /// The navigator must not walk a megabyte-long message on every render —
    /// that froze the whole app when a huge paste was opened.
    private final class CountingCharacters: Sequence, @unchecked Sendable {
        private let text: String
        private(set) var consumed = 0

        init(_ text: String) { self.text = text }

        struct Iterator: IteratorProtocol {
            let text: String
            let owner: CountingCharacters
            var index: String.Index

            mutating func next() -> Character? {
                guard index < text.endIndex else { return nil }
                defer { index = text.index(after: index) }
                owner.consumed += 1
                return text[index]
            }
        }

        func makeIterator() -> Iterator {
            Iterator(text: text, owner: self, index: text.startIndex)
        }
    }

    @Test("Нормализация превью читает только начало сообщения")
    func previewScanStopsAtTheLimit() {
        let huge = String(repeating: "a ", count: 200_000)
        let counter = CountingCharacters(huge)
        let result = UserMessageNavigatorLogic.normalizedPrefix(counter, limit: 100)
        #expect(result.text.count <= 100)
        #expect(result.hasMore)
        // The whole message is 400k characters — the scan must stop early.
        #expect(counter.consumed <= 250)
    }

    @Test("Превью огромного сообщения остаётся коротким")
    func previewOfHugeMessage() {
        let huge = String(repeating: "word ", count: 100_000)
        let preview = UserMessageNavigatorLogic.preview(for: message("big", content: huge))
        #expect(preview.hasSuffix("…"))
        #expect(preview.count <= 101)
    }

    // MARK: - U7: центрирование текущего сообщения

    @Test("Длинный список получает отступ, чтобы первая/последняя запись центрировалась")
    func longListGetsCenteringPadding() {
        // 23+ сообщений — список выше вьюпорта навигатора (~280pt).
        #expect(UserMessageNavigatorLogic.verticalPadding(itemCount: 23) == 120)
        #expect(UserMessageNavigatorLogic.verticalPadding(itemCount: 12) == 120)
    }

    @Test("Короткий список не получает пустых полей")
    func shortListHasNoPadding() {
        #expect(UserMessageNavigatorLogic.verticalPadding(itemCount: 11) == 0)
        #expect(UserMessageNavigatorLogic.verticalPadding(itemCount: 1) == 0)
        #expect(UserMessageNavigatorLogic.verticalPadding(itemCount: 0) == 0)
    }
}
