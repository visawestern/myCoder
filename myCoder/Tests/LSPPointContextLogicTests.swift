import Foundation
import Testing
@testable import myCoder

/// TDD for plan item 10: LSP-assisted point context — real server facts enter
/// the pack in a clearly-sourced section; an unavailable server yields no
/// facts and no section (honest skip); the section never duplicates code.
@Suite("LSP point context — facts, section, graceful absence")
struct LSPPointContextLogicTests {

    @Test("Facts collect only non-empty server reports")
    func factsCollectReports() async {
        let facts = await LSPPointContextLogic.facts(
            candidates: ["A.swift", "B.swift", "C.swift"],
            projectRoot: "/proj",
            diagnostics: { path, _ in
                switch path {
                case "A.swift": return "A.swift:1:1: warning: unused variable"
                case "B.swift": return nil   // server unavailable / nothing
                default: return ""
                }
            }
        )
        #expect(facts.count == 1)
        #expect(facts[0].path == "A.swift")
        #expect(facts[0].text.contains("unused variable"))
    }

    @Test("Facts probe is bounded")
    func factsBounded() async {
        let paths = Array(0..<20).map { "F\($0).swift" }
        let facts = await LSPPointContextLogic.facts(
            candidates: paths,
            projectRoot: "/proj",
            limit: 5,
            diagnostics: { path, _ in "report for \(path)" }
        )
        #expect(facts.count == 5)
    }

    @Test("Section carries an explicit source marker and no code duplication")
    func sectionSourceMarker() {
        let built = LSPPointContextLogic.section(facts: [
            .init(path: "A.swift", text: "A.swift:2:1: error: bad"),
        ])
        let section = try? #require(built)
        #expect(section?.title.contains("LSP") == true)
        #expect(section?.title.contains("источник") == true)
        #expect(section?.body.contains("A.swift") == true)
        // Facts are diagnostics, not code blocks — no ``` fences, no file body.
        #expect(section?.body.contains("````") == false)
    }

    @Test("No facts ⇒ no section (server unavailable is honest absence)")
    func noFactsNoSection() {
        #expect(LSPPointContextLogic.section(facts: []) == nil)
    }

    @Test("Candidate paths rank query-matching files first")
    func candidatePathsRanking() {
        let records = [
            FileIndexRecord(path: "src/UserStore.swift", hash: "h", size: 10, lastModified: 0, language: "swift"),
            FileIndexRecord(path: "src/Session.swift", hash: "h", size: 10, lastModified: 0, language: "swift"),
            FileIndexRecord(path: "docs/readme.md", hash: "h", size: 10, lastModified: 0, language: "markdown"),
        ]
        let paths = LSPPointContextLogic.candidatePaths(records: records, query: "UserStore")
        #expect(paths.first == "src/UserStore.swift")
        #expect(paths.count == 1)
    }

    @Test("Compile embeds the LSP section when provided")
    func compileEmbedsLspSection() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = ContextBoardBuilder.build(projectPath: root.path, records: [])
        let lspSection = LSPPointContextLogic.section(facts: [
            .init(path: "A.swift", text: "A.swift:1:1: warning: x"),
        ])
        let pack = TurnContextCompiler.compile(
            message: "почини A",
            board: board,
            projectRoot: root.path,
            budgetTokens: 4000,
            lspSection: lspSection
        )
        #expect(pack.text.contains("Диагностика LSP"))
        #expect(pack.text.contains("A.swift:1:1"))
    }

    @Test("Compile without LSP facts never fabricates a section")
    func compileWithoutLspStaysSilent() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = ContextBoardBuilder.build(projectPath: root.path, records: [])
        let pack = TurnContextCompiler.compile(
            message: "почини A",
            board: board,
            projectRoot: root.path,
            budgetTokens: 4000,
            lspSection: nil
        )
        #expect(!pack.text.contains("Диагностика LSP"))
    }

    // MARK: - Helpers

    private func makeTempProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lsp-point-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
