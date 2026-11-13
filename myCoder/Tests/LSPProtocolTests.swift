import Foundation
import Testing
@testable import myCoder

/// Pure LSP protocol pieces: framing, language mapping, positions, URIs and
/// the compact diagnostics report the agent receives. Runtime process tests
/// live in `LSPClientLiveTests`.
@Suite("LSP protocol")
struct LSPProtocolTests {

    // MARK: - JSON-RPC framing

    @Test func framesJSONRPCWithExactContentLength() throws {
        let json = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#.utf8)
        let frame = LSPMessageCodec.frame(json: json)
        let text = String(decoding: frame, as: UTF8.self)
        #expect(text.hasPrefix("Content-Length: \(json.count)\r\n\r\n"))
        #expect(text.hasSuffix(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#))
    }

    @Test func decodesMultipleFramesFromOneBuffer() throws {
        let first = LSPMessageCodec.frame(json: Data(#"{"id":1,"result":null}"#.utf8))
        let second = LSPMessageCodec.frame(json: Data(#"{"method":"initialized"}"#.utf8))
        var buffer = Data()
        buffer.append(first)
        buffer.append(second)

        let decoded = LSPMessageCodec.decode(buffer: buffer)
        #expect(decoded.messages.count == 2)
        #expect(decoded.remaining.isEmpty)
        #expect(String(decoding: decoded.messages[0], as: UTF8.self).contains(#""id":1"#))
        #expect(String(decoding: decoded.messages[1], as: UTF8.self).contains("initialized"))
    }

    @Test func keepsIncompleteFrameInRemainingBuffer() throws {
        let frame = LSPMessageCodec.frame(json: Data(#"{"id":7,"result":{"ok":true}}"#.utf8))
        let split = frame.count / 2
        let decoded = LSPMessageCodec.decode(buffer: frame.prefix(split))
        #expect(decoded.messages.isEmpty)
        #expect(decoded.remaining.count == split)

        var buffer = decoded.remaining
        buffer.append(frame.suffix(from: split))
        let complete = LSPMessageCodec.decode(buffer: buffer)
        #expect(complete.messages.count == 1)
        #expect(complete.remaining.isEmpty)
    }

    @Test func headerLookupIsCaseInsensitive() throws {
        let body = Data(#"{"id":2}"#.utf8)
        let raw = Data("content-length: \(body.count)\r\n\r\n".utf8) + body
        let decoded = LSPMessageCodec.decode(buffer: raw)
        #expect(decoded.messages.count == 1)
    }

    // MARK: - Language mapping

    @Test func mapsCommonExtensionsToLanguageIDs() {
        let cases: [(String, String, String)] = [
            ("a.swift", "swift", "Swift"),
            ("a.ts", "typescript", "TypeScript"),
            ("a.tsx", "typescriptreact", "TypeScript"),
            ("a.js", "javascript", "JavaScript"),
            ("a.py", "python", "Python"),
            ("a.rs", "rust", "Rust"),
            ("a.go", "go", "Go"),
            ("a.c", "c", "C"),
            ("a.h", "c", "C"),
            ("a.cpp", "cpp", "C++"),
            ("a.hpp", "cpp", "C++"),
            ("a.m", "objective-c", "Objective-C"),
            ("a.mm", "objective-cpp", "Objective-C"),
            ("a.java", "java", "Java"),
            ("a.html", "html", "HTML"),
            ("a.css", "css", "CSS"),
            ("a.json", "json", "JSON"),
            ("a.zig", "zig", "Zig")
        ]
        for (path, id, display) in cases {
            let language = LSPLanguageMap.language(forPath: path)
            #expect(language?.id == id, "\(path) → \(id)")
            #expect(language?.displayName == display, "\(path) → \(display)")
        }
        #expect(LSPLanguageMap.language(forPath: "README.md") == nil)
    }

    @Test func matchesConfiguredServerLanguagesCaseInsensitively() throws {
        let swift = try #require(LSPLanguageMap.language(forPath: "x.swift"))
        #expect(LSPLanguageMap.serverSupports(languages: ["Swift", "Objective-C"], language: swift))
        #expect(!LSPLanguageMap.serverSupports(languages: ["Rust"], language: swift))
    }

    // MARK: - Positions and URIs

    @Test func convertsOneBasedPositionToZeroBasedUTF16() {
        let text = "let 🐟 = 1\nprint(🐟)"
        let position = LSPPositionLogic.position(line: 2, column: 7, in: text)
        // "print(" is 6 UTF-16 units; column 7 is the fish's first unit.
        #expect(position.line == 1)
        #expect(position.character == 6)
    }

    @Test func clampsPositionToLineBounds() {
        let text = "abc\ndef"
        let position = LSPPositionLogic.position(line: 99, column: 99, in: text)
        #expect(position.line == 1)
        #expect(position.character == 3)
    }

    @Test func fileURIRoundTripsPathsWithSpaces() throws {
        let path = "/tmp/my project/a b.swift"
        let uri = LSPDocumentURI.make(path: path)
        #expect(uri.hasPrefix("file://"))
        #expect(uri.contains("my%20project"))
        #expect(LSPDocumentURI.path(fromURI: uri) == path)
    }

    // MARK: - Diagnostics report

    @Test func formatsErrorsAndWarningsWithOneBasedPositions() {
        let diagnostics = [
            LSPDiagnostic(
                range: LSPRange(start: LSPPosition(line: 11, character: 4),
                                end: LSPPosition(line: 11, character: 9)),
                severity: 1, message: "cannot find 'value' in scope", source: "sourcekit-lsp"),
            LSPDiagnostic(
                range: LSPRange(start: LSPPosition(line: 20, character: 0),
                                end: LSPPosition(line: 20, character: 3)),
                severity: 2, message: "variable 'x' was never used", source: "sourcekit-lsp")
        ]
        let text = LSPDiagnosticsFormatter.summary(path: "Sources/A.swift", diagnostics: diagnostics)
        #expect(text.contains("1 error"))
        #expect(text.contains("1 warning"))
        #expect(text.contains("12:5"))
        #expect(text.contains("21:1"))
        #expect(text.contains("cannot find 'value' in scope"))
        #expect(text.contains("[sourcekit-lsp]"))
    }

    @Test func reportsCleanFileAndCapsLongLists() {
        #expect(LSPDiagnosticsFormatter.summary(path: "a.swift", diagnostics: [])
            .contains("no errors or warnings"))

        let many = (0..<30).map { index in
            LSPDiagnostic(
                range: LSPRange(start: LSPPosition(line: index, character: 0),
                                end: LSPPosition(line: index, character: 1)),
                severity: 1, message: "error \(index)", source: "lsp")
        }
        let text = LSPDiagnosticsFormatter.summary(path: "a.swift", diagnostics: many, maxItems: 5)
        #expect(text.contains("30 errors"))
        #expect(text.contains("error 0"))
        #expect(!text.contains("error 9"))
        #expect(text.contains("and 25 more"))
    }
}
