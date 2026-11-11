import Testing
import Foundation
import AppKit
@testable import myCoder

/// Пути и имена файлов в обычном тексте ответа (не только в inline-коде)
/// получают `.chatFilePath` и становятся кликабельными: клик открывает меню
/// «Открыть с помощью / Показать в Finder» (user request 2026-10-31).
@MainActor
@Suite("Кликабельные пути в тексте ответа")
struct ChatFileClickablePathsTests {

    private func makeProject() throws -> (URL, String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickpaths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "import Foundation\nfinal class A {}"
            .write(to: root.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "let x = 1"
            .write(to: root.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        return (root, root.path)
    }

    @Test("Путь посреди обычного текста помечается chatFilePath")
    func plainTextPathGetsAttribute() throws {
        let (root, projectRoot) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let text = "Посмотри файл Sources/App.swift и скажи, что там."
        let attributed = MarkdownAttributedStringBuilder.build(
            text: text,
            fontSize: 14,
            textColor: .primary,
            projectRoot: projectRoot
        )

        var found: String?
        attributed.enumerateAttribute(.chatFilePath, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let path = value as? String { found = path }
        }
        #expect(found != nil, "путь в обычном тексте должен быть кликабельным")
        #expect(found?.hasSuffix("Sources/App.swift") == true)
        #expect(FileManager.default.fileExists(atPath: found ?? ""))
    }

    @Test("Имя файла с расширением из той же папки помечается")
    func relativeFilenameFromProjectRootGetsAttribute() throws {
        let (root, projectRoot) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let text = "Изменил App.swift."
        let attributed = MarkdownAttributedStringBuilder.build(
            text: text,
            fontSize: 14,
            textColor: .primary,
            projectRoot: projectRoot
        )
        var found: String?
        attributed.enumerateAttribute(.chatFilePath, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let path = value as? String { found = path }
        }
        #expect(found != nil)
        #expect(FileManager.default.fileExists(atPath: found ?? ""))
        #expect(found == root.appendingPathComponent("App.swift").path)
    }

    @Test("Несуществующие имена не помечаются")
    func nonexistentPathIsNotMarked() throws {
        let (root, projectRoot) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let text = "Такого файла нет: Nope.swift, и таких слов тоже: hello world."
        let attributed = MarkdownAttributedStringBuilder.build(
            text: text,
            fontSize: 14,
            textColor: .primary,
            projectRoot: projectRoot
        )
        var count = 0
        attributed.enumerateAttribute(.chatFilePath, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if value as? String != nil { count += 1 }
        }
        #expect(count == 0)
    }

    @Test("Папка из проекта тоже кликабельна")
    func folderIsClickable() throws {
        let (root, projectRoot) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let text = "Структура: Sources"
        let attributed = MarkdownAttributedStringBuilder.build(
            text: text,
            fontSize: 14,
            textColor: .primary,
            projectRoot: projectRoot
        )
        var found: String?
        attributed.enumerateAttribute(.chatFilePath, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let path = value as? String { found = path }
        }
        #expect(found != nil)
        #expect(found == root.appendingPathComponent("Sources").path)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: found ?? "", isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("Inline-код по-прежнему помечается")
    func inlineCodeStillGetsAttribute() throws {
        let (root, projectRoot) = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let text = "Смотри `Sources/App.swift` тут."
        let attributed = MarkdownAttributedStringBuilder.build(
            text: text,
            fontSize: 14,
            textColor: .primary,
            projectRoot: projectRoot
        )
        var found: String?
        attributed.enumerateAttribute(.chatFilePath, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let path = value as? String { found = path }
        }
        #expect(found?.hasSuffix("Sources/App.swift") == true)
    }
}
