import Testing
import Foundation
import AppKit
@testable import myCoder

/// Кликабельные пути в тексте ответа. Вью рисует подчёркнутый фиолетовый
/// токен, но клик обязан что-то делать, а курсор — становиться «пальцем».
///
/// Здесь фиксируются три причины, из-за которых клик раньше не работал:
/// 1) у токена не было ссылки (`.link`), поэтому `NSTextView` не считал его
///    кликабельным и не показывал курсор-палец;
/// 2) меню открывалось в координатах окна, а `NSMenu.popUp` при `in: nil`
///    ждёт координаты экрана — меню уезжало за пределы видимой области;
/// 3) попадание в границу слова возвращало соседний символ, а не путь.
@MainActor
@Suite("Кликабельные пути: ссылка, курсор и попадание")
struct ChatFileLinkLogicTests {

    // MARK: - Ссылка для пути

    @Test("Абсолютный путь превращается в ссылку со своим схемным именем")
    func absolutePathBecomesLink() {
        let link = ChatFileLinkLogic.url(forPath: "/Users/apple/projects/App.swift")
        #expect(link != nil)
        #expect(link?.scheme == ChatFileLinkLogic.scheme)
        #expect(ChatFileLinkLogic.path(fromLink: link) == "/Users/apple/projects/App.swift")
    }

    @Test("Пробелы, кириллица, решётка, вопрос и процент переживают round-trip")
    func trickyCharactersRoundTrip() {
        let paths = [
            "/Users/apple/Мои проекты/App.swift",
            "/tmp/a b/Файл №1.swift",
            "/tmp/hash#name.swift",
            "/tmp/query?name.swift",
            "/tmp/percent%name.swift",
            "/tmp/&plus+plus.swift"
        ]
        for path in paths {
            guard let link = ChatFileLinkLogic.url(forPath: path) else {
                Issue.record("путь не превратился в ссылку: \(path)")
                continue
            }
            #expect(ChatFileLinkLogic.path(fromLink: link) == path, "потерян путь: \(path)")
        }
    }

    @Test("Относительный или пустой путь не становится ссылкой")
    func relativePathIsRejected() {
        #expect(ChatFileLinkLogic.url(forPath: "Sources/App.swift") == nil)
        #expect(ChatFileLinkLogic.url(forPath: "") == nil)
        #expect(ChatFileLinkLogic.url(forPath: "   ") == nil)
    }

    @Test("Чужая ссылка не выдаётся за файл чата")
    func foreignLinkIsRejected() {
        let web = URL(string: "https://example.com/App.swift")!
        #expect(ChatFileLinkLogic.path(fromLink: web) == nil)
        #expect(ChatFileLinkLogic.path(fromLink: "https://example.com") == nil)
        #expect(ChatFileLinkLogic.path(fromLink: 42) == nil)
    }

    @Test("Ссылка с непустым host отклоняется (mycoder-file://host/path)")
    func hostfulLinkIsRejected() {
        let url = URL(string: "mycoder-file://host/Users/x/App.swift")!
        #expect(ChatFileLinkLogic.path(fromLink: url) == nil)
        #expect(ChatFileLinkLogic.path(fromLink: "mycoder-file://host/Users/x/App.swift") == nil)
    }

    @Test("Ссылка принимается и как URL, и как строка (делегат AppKit даёт оба)")
    func linkAcceptsURLAndString() {
        let url = ChatFileLinkLogic.url(forPath: "/tmp/App.swift")!
        #expect(ChatFileLinkLogic.path(fromLink: url) == "/tmp/App.swift")
        #expect(ChatFileLinkLogic.path(fromLink: url.absoluteString) == "/tmp/App.swift")
    }

    // MARK: - Разметка attributed-строки

    private func makeProject() throws -> (URL, String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("filelink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "let x = 1".write(
            to: root.appendingPathComponent("App.swift"),
            atomically: true,
            encoding: .utf8
        )
        return (root, root.path)
    }

    @Test("Путь в прозе получает и chatFilePath, и ссылку")
    func prosePathGetsLink() throws {
        let (root, projectRoot) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let attributed = MarkdownAttributedStringBuilder.build(
            text: "Изменил App.swift и всё.",
            fontSize: 14,
            textColor: .primary,
            projectRoot: projectRoot
        )
        guard let range = ChatFileLinkLogic.clickableRanges(in: attributed).first else {
            Issue.record("нет кликабельного диапазона")
            return
        }
        #expect(attributed.attribute(.link, at: range.location, effectiveRange: nil) != nil,
                "без .link NSTextView не показывает палец и не шлёт клик делегату")
    }

    @Test("Inline-код с путём тоже получает ссылку")
    func inlineCodeGetsLink() throws {
        let (root, projectRoot) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let attributed = MarkdownAttributedStringBuilder.build(
            text: "Смотри `App.swift` тут.",
            fontSize: 14,
            textColor: .primary,
            projectRoot: projectRoot
        )
        guard let range = ChatFileLinkLogic.clickableRanges(in: attributed).first else {
            Issue.record("нет кликабельного диапазона")
            return
        }
        #expect(attributed.attribute(.link, at: range.location, effectiveRange: nil) != nil)
    }

    // MARK: - Попадание клика

    @Test("Индекс на границе слова не считается попаданием в путь")
    func indexRightAfterPathMisses() throws {
        let (root, projectRoot) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let attributed = MarkdownAttributedStringBuilder.build(
            text: "Изменил App.swift и всё.",
            fontSize: 14,
            textColor: .primary,
            projectRoot: projectRoot
        )
        guard let range = ChatFileLinkLogic.clickableRanges(in: attributed).first else {
            Issue.record("нет кликабельного диапазона")
            return
        }
        #expect(ChatFileLinkLogic.absolutePath(in: attributed, at: range.location) != nil)
        #expect(ChatFileLinkLogic.absolutePath(in: attributed, at: NSMaxRange(range) - 1) != nil)
        #expect(ChatFileLinkLogic.absolutePath(in: attributed, at: NSMaxRange(range)) == nil,
                "индекс сразу после пути — это уже пробел, а не файл")
    }

    @Test("Клик по обычному тексту и за пределами строки не открывает меню")
    func plainTextAndOutOfBoundsMiss() throws {
        let (root, projectRoot) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let attributed = MarkdownAttributedStringBuilder.build(
            text: "Изменил App.swift и всё.",
            fontSize: 14,
            textColor: .primary,
            projectRoot: projectRoot
        )
        #expect(ChatFileLinkLogic.absolutePath(in: attributed, at: 0) == nil)
        #expect(ChatFileLinkLogic.absolutePath(in: attributed, at: -1) == nil)
        #expect(ChatFileLinkLogic.absolutePath(in: attributed, at: attributed.length) == nil)
    }

    // MARK: - Координаты меню

    @Test("Точка меню переводится из координат окна в координаты экрана")
    func menuPointIsConvertedToScreen() {
        let windowOrigin = NSPoint(x: 100, y: 40)
        let inWindow = NSPoint(x: 12, y: 7)
        #expect(ChatFileLinkLogic.screenPoint(windowOrigin: windowOrigin, inWindow: inWindow)
                == NSPoint(x: 112, y: 47))
    }
}
