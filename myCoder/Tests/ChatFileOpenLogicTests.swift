import Testing
import Foundation
@testable import myCoder

@Suite("Chat file open logic")
struct ChatFileOpenLogicTests {

    @Test("Path-like tokens are recognized")
    func pathLikeTokens() {
        #expect(ChatFileOpenLogic.looksLikeFilePath("src/main.swift"))
        #expect(ChatFileOpenLogic.looksLikeFilePath("/Users/apple/project/file.txt"))
        #expect(ChatFileOpenLogic.looksLikeFilePath("~/Documents/report.pdf"))
        #expect(ChatFileOpenLogic.looksLikeFilePath("README.md"))
        #expect(ChatFileOpenLogic.looksLikeFilePath("package.json"))
        #expect(ChatFileOpenLogic.looksLikeFilePath("./build/app"))
        #expect(ChatFileOpenLogic.looksLikeFilePath("../notes.org"))
    }

    @Test("Non-path tokens are rejected")
    func nonPathTokens() {
        #expect(!ChatFileOpenLogic.looksLikeFilePath("https://example.com/file.txt"))
        #expect(!ChatFileOpenLogic.looksLikeFilePath("mailto:user@example.com"))
        #expect(!ChatFileOpenLogic.looksLikeFilePath("hello"))
        #expect(!ChatFileOpenLogic.looksLikeFilePath(""))
        #expect(!ChatFileOpenLogic.looksLikeFilePath("main"))
        #expect(!ChatFileOpenLogic.looksLikeFilePath("very_long_identifier_without_extension"))
    }

    @Test("Absolute paths resolve when the file exists")
    func absoluteResolution() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chat-open-\(UUID().uuidString).txt")
        try? Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ChatFileOpenLogic.resolveFilePath(url.path, projectRoot: nil) == url.path)
        #expect(ChatFileOpenLogic.resolveFilePath("/nonexistent/\(UUID().uuidString).txt", projectRoot: nil) == nil)
    }

    @Test("Relative paths resolve against the project root")
    func relativeResolution() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chat-open-root-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("docs/readme.md")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ChatFileOpenLogic.resolveFilePath("docs/readme.md", projectRoot: root.path) == file.path)
        #expect(ChatFileOpenLogic.resolveFilePath("docs/readme.md", projectRoot: nil) == nil)
        #expect(ChatFileOpenLogic.resolveFilePath("missing.md", projectRoot: root.path) == nil)
    }

    @Test("Tilde paths expand to the home directory")
    func tildeResolution() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(ChatFileOpenLogic.resolveFilePath("~", projectRoot: nil) == home.path)
    }

    @Test("Default application is ordered first without duplicates")
    func applicationOrdering() {
        let a = URL(fileURLWithPath: "/Applications/A.app")
        let b = URL(fileURLWithPath: "/Applications/B.app")
        let c = URL(fileURLWithPath: "/Applications/C.app")
        #expect(ChatFileOpenLogic.orderedApplications(default: b, candidates: [a, b, c]) == [b, a, c])
        #expect(ChatFileOpenLogic.orderedApplications(default: nil, candidates: [a, a, b]) == [a, b])
        #expect(ChatFileOpenLogic.orderedApplications(default: nil, candidates: []).isEmpty)
    }

    @Test("Application names are readable")
    func applicationNames() {
        #expect(ChatFileOpenLogic.applicationName(at: URL(fileURLWithPath: "/Applications/Xcode.app")) == "Xcode")
        #expect(ChatFileOpenLogic.applicationName(at: URL(fileURLWithPath: "/Applications/Safari.app")) == "Safari")
    }
}
