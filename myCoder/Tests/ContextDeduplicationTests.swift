import Testing
import Foundation
@testable import myCoder

/// Контекст перед отправкой не должен содержать один и тот же файл дважды и
/// повторять смыслы из диалога и из файлов.
@Suite("Дедупликация контекста")
struct ContextDeduplicationTests {

    private func file(_ path: String, _ body: String) -> ContextSection {
        ContextSection(title: path, body: "````\n\(body)\n````")
    }

    @Test("Один блок на файл: кандидат и зависимость не дублируются")
    func oneBlockPerFile() {
        let sections = [
            ContextSection(title: "Запрос", body: "найди X"),
            file("Sources/A.swift", "struct A { let x = 1 }"),
            ContextSection(title: "Sources/A.swift — зависимость",
                           body: "````\nstruct A { let y = 2 }\n````")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 2)
        #expect(result.dropped.contains {
            $0.path == "Sources/A.swift" && $0.reason.contains("дубликат файла")
        })
    }

    @Test("Точный повтор содержимого удаляется")
    func exactDuplicateBody() {
        let sections = [
            ContextSection(title: "Память проекта", body: "факт один"),
            ContextSection(title: "Другая секция", body: "  факт   один ")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 1)
        #expect(result.dropped.count == 1)
    }

    @Test("Строки из файлового блока не повторяются в истории чата")
    func narrativeLinesAlreadyInFiles() {
        let line = "let store = MessageStore() // единственный экземпляр на всё приложение"
        let sections = [
            file("Sources/A.swift", line),
            ContextSection(title: "История чата", body: "1. [Ассистент]\n   - \(line)")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        // Секция остаётся (в ней есть строка без дубля), но повторённая
        // строка из файла из неё удалена.
        #expect(result.sections.count == 2)
        let history = result.sections.first { $0.title == "История чата" }
        #expect(history?.body.contains("MessageStore()") == false)
        #expect(history?.body.contains("1. [Ассистент]") == true)
    }

    @Test("Запрос пользователя никогда не удаляется")
    func requestIsProtected() {
        let sections = [
            ContextSection(title: "Запрос", body: "одинаковый"),
            ContextSection(title: "Запрос", body: "одинаковый")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 2)
    }

    @Test("Разные файлы с общим boilerplate остаются оба")
    func differentFilesKept() {
        let boiler = String(repeating: "import Foundation // общий заголовок файла\n", count: 6)
        let sections = [
            file("Sources/A.swift", boiler + "struct A {}"),
            file("Sources/B.swift", boiler + "struct B {}")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 2)
    }

    @Test("Смысловой дубль в повествовательных секциях удаляется")
    func semanticDuplicateNarrative() {
        let text = String(repeating: "модель должна проверить контракт и зависимости перед правкой ", count: 6)
        let sections = [
            ContextSection(title: "Инструкции задачи", body: text),
            ContextSection(title: "Скилл", body: text + "дополнительное слово")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 1)
        #expect(result.dropped.contains { $0.reason.contains("смысловой") })
    }

    @Test("filePath распознаёт файл и зависимость, но не повествование")
    func filePathDetection() {
        #expect(ContextDeduplication.filePath(in: file("A/B.swift", "code")) == "A/B.swift")
        #expect(ContextDeduplication.filePath(
            in: ContextSection(title: "A/B.swift — зависимость", body: "````\ncode\n````")
        ) == "A/B.swift")
        #expect(ContextDeduplication.filePath(
            in: ContextSection(title: "История чата", body: "текст")
        ) == nil)
    }

    @Test("Нумерованные строки файла удаляются из повествования")
    func numberedFileLinesMatchNarrative() {
        // Материализатор нумерует строки кода («42 | let x = …»), а диалог
        // цитирует ту же строку без номера — обе формы должны схлопываться.
        let codeLine = "final class UserStore { private var cache: [String: Int] = [:] }"
        let sections = [
            file("Sources/UserStore.swift", "42 | \(codeLine)"),
            ContextSection(title: "История чата", body: "описание\n\(codeLine)")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 2)
        let history = result.sections.first { $0.title == "История чата" }
        #expect(history?.body.contains(codeLine) == false)
        #expect(history?.body.contains("описание") == true)
    }

    @Test("Повествование, целиком состоящее из строк файла, отбрасывается")
    func fullyRedundantNarrativeDropped() {
        let a = "let store = AppState.shared.store // единственная точка доступа ко всем данным приложения"
        let b = "private func flushPendingWrites() throws { try database.commit() } // атомарный коммит"
        let sections = [
            file("Sources/A.swift", "110 | \(a)\n111 | \(b)"),
            ContextSection(title: "История чата", body: "\(a)\n\(b)")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 1)
        #expect(result.dropped.contains { $0.reason.contains("дубликат содержимого из файлов") })
    }

    @Test("Разные пути с идентичным содержимым — остаётся один блок")
    func identicalBodyAcrossFilesDropped() {
        let body = "одинаковый код " + String(repeating: "x", count: 80)
        let sections = [
            file("Sources/A.swift", body),
            file("Sources/B.swift", body)
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 1)
        #expect(result.dropped.contains { $0.reason.contains("дубликат содержимого") })
    }

    @Test("Один и тот же путь дважды — второй блок отбрасывается")
    func samePathTwice() {
        let sections = [
            file("Sources/A.swift", "struct A { let x = 1 }"),
            file("Sources/A.swift", "struct A { let y = 2 }")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 1)
        #expect(result.dropped.contains { $0.reason.contains("дубликат файла") })
    }

    @Test("Повествование-подмножество более раннего удаляется")
    func semanticContainment() {
        let sentence = "локальная модель должна собрать атомарную задачу строго по контракту refs без кода "
        let sections = [
            ContextSection(title: "Инструкции задачи", body: String(repeating: sentence, count: 8)),
            ContextSection(title: "Память проекта", body: String(repeating: sentence, count: 4))
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.count == 1)
        #expect(result.dropped.contains { $0.reason.contains("смысловой") })
    }

    @Test("Порядок секций после дедупликации сохраняется")
    func orderPreserved() {
        let sections = [
            file("Sources/A.swift", "struct A {}"),
            ContextSection(title: "История чата", body: "факт"),
            file("Sources/A.swift", "struct A { let x = 1 }"),
            ContextSection(title: "Скилл", body: "навык")
        ]
        let result = ContextDeduplication.deduplicate(sections)
        #expect(result.sections.map(\.title) == ["Sources/A.swift", "История чата", "Скилл"])
    }
}
