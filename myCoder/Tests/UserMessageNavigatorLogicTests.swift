import Testing
import Foundation
@testable import myCoder

/// Навигатор по сообщениям пользователя: фильтрация user-сообщений,
/// превью (обрезка и нормализация пробелов), номера кнопок и шаги
/// перехода.
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
}
