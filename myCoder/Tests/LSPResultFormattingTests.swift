import Foundation
import Testing
@testable import myCoder

/// Pure formatting for LSP JSON results + deterministic server selection.
/// The live process test lives in `LSPClientLiveTests`.
@Suite("LSP result formatting and selection")
struct LSPResultFormattingTests {

    private func json(_ raw: String) -> Any {
        (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) ?? NSNull()
    }

    // MARK: - Locations

    @Test func formatsSingleLocationWithOneBasedPosition() {
        let result = json(#"""
        {"uri":"file:///project/Sources/A.swift",
         "range":{"start":{"line":11,"character":4},"end":{"line":11,"character":9}}}
        """#)
        let text = LSPResultFormatting.locations(result, kind: "definition")
        #expect(text.contains("1 definition:"))
        #expect(text.contains("/project/Sources/A.swift:12:5"))
    }

    @Test func formatsLocationArrayAndLocationLinks() {
        let result = json(#"""
        [
          {"uri":"file:///p/A.swift","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}},
          {"targetUri":"file:///p/B.swift","targetSelectionRange":{"start":{"line":4,"character":2},"end":{"line":4,"character":6}}}
        ]
        """#)
        let text = LSPResultFormatting.locations(result, kind: "reference")
        #expect(text.contains("2 references:"))
        #expect(text.contains("/p/A.swift:1:1"))
        #expect(text.contains("/p/B.swift:5:3"))
    }

    @Test func reportsEmptyLocationsExplicitly() {
        #expect(LSPResultFormatting.locations(nil, kind: "definition") == "no definitions found")
        #expect(LSPResultFormatting.locations(json("[]"), kind: "reference") == "no references found")
    }

    // MARK: - Hover

    @Test func formatsEveryHoverContentShape() {
        #expect(LSPResultFormatting.hover(json(#"{"contents":"func greet(name: String) -> String"}"#))
            .contains("greet(name: String)"))
        #expect(LSPResultFormatting.hover(json(#"{"contents":{"kind":"markdown","value":"**greet**"}}"#))
            .contains("**greet**"))
        #expect(LSPResultFormatting.hover(json(#"{"contents":[{"language":"swift","value":"let x = 1"},"plain"]}"#))
            .contains("let x = 1"))
        #expect(LSPResultFormatting.hover(json(#"{"contents":[]}"#)) == "no hover information")
        #expect(LSPResultFormatting.hover(nil) == "no hover information")
    }

    // MARK: - Completions

    @Test func formatsCompletionListWithDetailAndKind() {
        let result = json(#"""
        {"items":[
          {"label":"greet(name:)","kind":2,"detail":"String"},
          {"label":"count","kind":10}
        ]}
        """#)
        let text = LSPResultFormatting.completions(result, maxItems: 10)
        #expect(text.contains("2 completion items:"))
        #expect(text.contains("greet(name:) — String (Method)"))
        #expect(text.contains("count (Property)"))
    }

    @Test func capsCompletionList() {
        let items = (0..<40).map { #"{"label":"item\#($0)","kind":6}"# }.joined(separator: ",")
        let text = LSPResultFormatting.completions(json("[\(items)]"), maxItems: 5)
        #expect(text.contains("40 completion items:"))
        #expect(text.contains("item0"))
        #expect(!text.contains("item9"))
        #expect(text.contains("and 35 more"))
    }

    // MARK: - Server selection

    private func record(id: String, languages: [String], enabled: Bool = true) -> InstalledLSPRecord {
        InstalledLSPRecord(
            id: id,
            version: "1.0.0",
            installedAt: Date(timeIntervalSince1970: 0),
            source: .cursor,
            isEnabled: enabled,
            command: id,
            args: [],
            languages: languages
        )
    }

    @Test func selectsEnabledServerMatchingTheLanguage() {
        let records = [
            record(id: "rust-analyzer", languages: ["Rust"]),
            record(id: "sourcekit-lsp", languages: ["Swift", "Objective-C"])
        ]
        #expect(LSPServerSelection.select(records: records, path: "/p/A.swift")?.id == "sourcekit-lsp")
        #expect(LSPServerSelection.select(records: records, path: "/p/A.rs")?.id == "rust-analyzer")
    }

    @Test func ignoresDisabledServersAndUnknownExtensions() {
        let records = [
            record(id: "sourcekit-lsp", languages: ["Swift"], enabled: false),
            record(id: "clangd", languages: ["C"], enabled: true)
        ]
        #expect(LSPServerSelection.select(records: records, path: "/p/A.swift") == nil)
        #expect(LSPServerSelection.select(records: records, path: "/p/README.md") == nil)
    }

    @Test func selectionIsDeterministicAndIgnoresEmptyLanguageLists() {
        let records = [
            record(id: "z-server", languages: ["C"]),
            record(id: "a-server", languages: ["C"]),
            record(id: "empty", languages: [])
        ]
        #expect(LSPServerSelection.select(records: records, path: "/p/main.c")?.id == "a-server")
    }

    @Test func configuredLanguageMatchingIsCaseInsensitive() {
        let records = [record(id: "sourcekit-lsp", languages: ["swift"])]
        #expect(LSPServerSelection.select(records: records, path: "/p/A.swift")?.id == "sourcekit-lsp")
    }
}
