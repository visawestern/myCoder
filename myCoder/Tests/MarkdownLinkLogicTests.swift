import Foundation
import Testing
@testable import myCoder

/// Классификация назначений markdown-ссылок: веб-URL, локальные пути
/// (относительные, абсолютные, file://) и неподдерживаемые схемы (запрос
/// 2026-11-13: ссылки должны рендериться как ссылки, включая локальные пути).
@MainActor
@Suite("Классификация markdown-ссылок")
struct MarkdownLinkLogicTests {

    @Test("Веб-URL http/https классифицируются как web")
    func webURLs() {
        guard case .web(let url) = MarkdownLinkLogic.kind(for: "https://example.com/path?q=1") else {
            Issue.record("expected web")
            return
        }
        #expect(url.host == "example.com")

        guard case .web = MarkdownLinkLogic.kind(for: "http://example.com") else {
            Issue.record("expected web for http")
            return
        }
    }

    @Test("Регистр схемы не влияет")
    func schemeCaseInsensitive() {
        guard case .web = MarkdownLinkLogic.kind(for: "HTTPS://EXAMPLE.COM") else {
            Issue.record("expected web for uppercase scheme")
            return
        }
    }

    @Test("Относительные пути классифицируются как file")
    func relativePaths() {
        #expect(MarkdownLinkLogic.kind(for: "Sources/Foo.swift") == .file("Sources/Foo.swift"))
        #expect(MarkdownLinkLogic.kind(for: "./Foo.swift") == .file("./Foo.swift"))
        #expect(MarkdownLinkLogic.kind(for: "../A/B.swift") == .file("../A/B.swift"))
        #expect(MarkdownLinkLogic.kind(for: "Foo.swift") == .file("Foo.swift"))
    }

    @Test("Абсолютные и домашние пути классифицируются как file")
    func absolutePaths() {
        #expect(MarkdownLinkLogic.kind(for: "/Users/x/proj/Main.swift") == .file("/Users/x/proj/Main.swift"))
        #expect(MarkdownLinkLogic.kind(for: "~/Pictures/img.png") == .file("~/Pictures/img.png"))
    }

    @Test("file:// превращается в путь файла")
    func fileScheme() {
        #expect(MarkdownLinkLogic.kind(for: "file:///Users/x/a.png") == .file("/Users/x/a.png"))
    }

    @Test("Неподдерживаемые схемы и якоря классифицируются как unsupported")
    func unsupported() {
        #expect(MarkdownLinkLogic.kind(for: "mailto:a@b.com") == .unsupported)
        #expect(MarkdownLinkLogic.kind(for: "#section") == .unsupported)
        #expect(MarkdownLinkLogic.kind(for: "ftp://example.com") == .unsupported)
        #expect(MarkdownLinkLogic.kind(for: "") == .unsupported)
        #expect(MarkdownLinkLogic.kind(for: "   ") == .unsupported)
    }

    @Test("resolveFile возвращает путь только для существующего файла")
    func resolveFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "hello".write(to: root.appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)

        #expect(MarkdownLinkLogic.resolveFile("A.txt", projectRoot: root.path) == root.appendingPathComponent("A.txt").standardizedFileURL.path)
        #expect(MarkdownLinkLogic.resolveFile("Missing.txt", projectRoot: root.path) == nil)
    }
}
