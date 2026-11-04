import Testing
import Foundation
@testable import myCoder

/// Live API audit 2026-11-04: `TurnEvidence.graph → CodeIndexService.search`
/// re-ran the WHOLE incremental index pass (1009 file-state comparisons,
/// mtime touches, reparse and edge rebuild) on every call — and the context
/// pipeline calls it twice per turn (planner graph + compiler graph). A
/// `context-preview` on the real project took 59-60 s and often hit the
/// handler's 60 s deadline. A read-only search must not write; indexing is
/// event-driven (FSEvents watcher) and only a completely empty store needs a
/// first build here.
@Suite("Поиск по графу не переиндексирует проект")
struct CodeIndexSearchBudgetTests {

    @Test("Поиск индексирует только пустой стор")
    func searchIndexesOnlyEmptyStore() throws {
        let source = try RepoRoot.sourceText("myCoder/Sources/Services/CodeIndexService.swift")
        #expect(source.contains("counts().symbols == 0"),
                "полная индексация должна быть условной, а не на каждый поиск")
    }

    @Test("Первый поиск по свежему проекту всё ещё строит индекс и находит символ")
    func firstSearchStillFindsSymbol() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-search-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rel = "Sources/Audit.swift"
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = "final class AuditSearchMarker {}\nfunc auditSearchMarker() {}\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        let record = FileIndexRecord(path: rel, hash: "h1", size: text.utf8.count,
                                     lastModified: 1, language: "swift", searchableText: text)
        let hits = try CodeIndexService.search(projectPath: root.path, query: "auditSearchMarker", records: [record])
        #expect(!hits.isEmpty, "свежий стор должен проиндексироваться по первому поиску")
    }
}
