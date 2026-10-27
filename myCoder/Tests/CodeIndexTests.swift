import Testing
import Foundation
@testable import myCoder

/// The code graph must state only what source supports: exact edges where the
/// target is unambiguous, labelled heuristics where a convention was used, and
/// no unresolved placeholders in evidence. `read_symbol` must never show a line
/// number that was not verified against the file on disk.
@Suite("Граф кода — извлечение, БД, поиск и tools")
struct CodeIndexTests {

    // MARK: - Fixtures

    private let userStoreSource = """
    import Foundation

    final class UserStore {
        private var cache: [String: Int] = [:]

        func load(id: String) -> Int {
            cache[id] ?? 0
        }

        func reload() -> Int {
            load(id: "x")
        }
    }
    """

    private let appSource = """
    import Foundation
    import UserStore

    func bootstrap() -> Int {
        let store = UserStore()
        return store.load(id: "abc")
    }
    """

    private let testsSource = """
    import Testing

    @Test func testLoadReturnsZero() {
        #expect(UserStore().load(id: "missing") == 0)
    }
    """

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-codeindex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write(userStoreSource, "Sources/UserStore.swift", in: root)
        try write(appSource, "Sources/App.swift", in: root)
        try write(testsSource, "Tests/UserStoreTests.swift", in: root)
        return root
    }

    private func write(_ text: String, _ path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func records(in root: URL) -> [FileIndexRecord] {
        ProjectFileScanner.scan(root: root.path)
    }

    // MARK: - T1: symbols, spans and every edge kind

    @Test("T1: извлечение символов и рёбер declares/contains/calls/imports/tests")
    func extractsSymbolsAndEdges() {
        let store = CodeIndexExtractor.extract(
            path: "Sources/UserStore.swift",
            text: userStoreSource,
            language: "swift"
        )
        let app = CodeIndexExtractor.extract(
            path: "Sources/App.swift",
            text: appSource,
            language: "swift"
        )
        let tests = CodeIndexExtractor.extract(
            path: "Tests/UserStoreTests.swift",
            text: testsSource,
            language: "swift"
        )

        // Exact line spans: the closing brace belongs to the declaration.
        #expect(store.symbols.contains(CodeSymbol(
            path: "Sources/UserStore.swift", name: "UserStore",
            kind: "type", startLine: 3, endLine: 13
        )))
        #expect(store.symbols.contains(CodeSymbol(
            path: "Sources/UserStore.swift", name: "load",
            kind: "func", startLine: 6, endLine: 8
        )))
        #expect(store.symbols.contains(CodeSymbol(
            path: "Sources/UserStore.swift", name: "reload",
            kind: "func", startLine: 10, endLine: 12
        )))
        #expect(store.symbols.contains(CodeSymbol(
            path: "Sources/UserStore.swift", name: "cache",
            kind: "var", startLine: 4, endLine: 4
        )))

        #expect(store.imports.contains(CodeRawImport(module: "Foundation", line: 1)))
        #expect(app.imports.contains(CodeRawImport(module: "UserStore", line: 2)))
        #expect(store.calls.contains { $0.callee == "load" })

        let edges = CodeGraphBuilder.build(files: [store, app, tests])
        let userStoreID = CodeSymbol.makeID(
            path: "Sources/UserStore.swift", kind: "type", name: "UserStore", startLine: 3
        )
        let loadID = CodeSymbol.makeID(
            path: "Sources/UserStore.swift", kind: "func", name: "load", startLine: 6
        )
        let reloadID = CodeSymbol.makeID(
            path: "Sources/UserStore.swift", kind: "func", name: "reload", startLine: 10
        )
        let bootstrapID = CodeSymbol.makeID(
            path: "Sources/App.swift", kind: "func", name: "bootstrap", startLine: 4
        )
        let testID = CodeSymbol.makeID(
            path: "Tests/UserStoreTests.swift", kind: "func",
            name: "testLoadReturnsZero", startLine: 3
        )

        #expect(edges.contains(CodeEdge(
            from: "file:Sources/UserStore.swift", to: userStoreID,
            kind: .declares, confidence: .exact
        )))
        #expect(edges.contains(CodeEdge(
            from: userStoreID, to: loadID, kind: .contains, confidence: .exact
        )))
        #expect(edges.contains(CodeEdge(
            from: reloadID, to: loadID, kind: .calls, confidence: .exact
        )))
        #expect(edges.contains(CodeEdge(
            from: bootstrapID, to: loadID, kind: .calls, confidence: .exact
        )))
        #expect(edges.contains(CodeEdge(
            from: "file:Sources/App.swift", to: "file:Sources/UserStore.swift",
            kind: .imports, confidence: .exact
        )))
        #expect(edges.contains(CodeEdge(
            from: testID, to: loadID, kind: .tests, confidence: .exact
        )))
    }

    @Test("T1: атрибуты Swift не прячут объявление, блок Python заканчивается по отступу")
    func attributesAndPythonBlocks() {
        let swift = """
        @MainActor
        final class Store {
            @discardableResult
            func load() -> Int { 0 }
        }
        """
        let swiftBlocks = SymbolNameExtractor.blocks(in: swift, language: "swift")
        #expect(swiftBlocks.contains(SymbolBlock(name: "Store", kind: "type", startLine: 2, endLine: 5)))
        #expect(swiftBlocks.contains(SymbolBlock(name: "load", kind: "func", startLine: 4, endLine: 4)))

        let python = """
        class Service:
            def query(self):
                return 1

        def main():
            pass
        """
        let pythonBlocks = SymbolNameExtractor.blocks(in: python, language: "python")
        #expect(pythonBlocks.contains(SymbolBlock(name: "Service", kind: "type", startLine: 1, endLine: 3)))
        #expect(pythonBlocks.contains(SymbolBlock(name: "query", kind: "func", startLine: 2, endLine: 3)))
        #expect(pythonBlocks.contains(SymbolBlock(name: "main", kind: "func", startLine: 5, endLine: 6)))
    }

    // MARK: - T2: confidence

    @Test("T2: exact при одном кандидате, heuristic при неоднозначности, unresolved без цели")
    func confidenceIsLabelled() {
        let first = CodeIndexExtractor.extract(
            path: "Sources/A.swift",
            text: "func render() -> Int {\n    1\n}",
            language: "swift"
        )
        let second = CodeIndexExtractor.extract(
            path: "Sources/B.swift",
            text: "func render() -> Int {\n    2\n}",
            language: "swift"
        )
        let caller = CodeIndexExtractor.extract(
            path: "Sources/C.swift",
            text: "func draw() {\n    render()\n    missingHelper()\n}",
            language: "swift"
        )
        let edges = CodeGraphBuilder.build(files: [first, second, caller])

        let aRender = CodeSymbol.makeID(
            path: "Sources/A.swift", kind: "func", name: "render", startLine: 1
        )
        let heuristic = edges.first {
            $0.kind == .calls && $0.confidence == .heuristic
        }
        #expect(heuristic?.to == aRender)
        #expect(edges.contains {
            $0.to == "unresolved:missingHelper" && $0.confidence == .unresolved
        })

        // A same-file candidate wins over the ambiguous cross-file ones.
        let local = CodeIndexExtractor.extract(
            path: "Sources/D.swift",
            text: "func render() -> Int { 3 }\nfunc draw() {\n    render()\n}",
            language: "swift"
        )
        let localEdges = CodeGraphBuilder.build(files: [first, second, local])
        let localRender = CodeSymbol.makeID(
            path: "Sources/D.swift", kind: "func", name: "render", startLine: 1
        )
        #expect(localEdges.contains(CodeEdge(
            from: "symbol:Sources/D.swift#func:draw@2",
            to: localRender,
            kind: .calls,
            confidence: .exact
        )))
    }

    @Test("T2: unresolved-рёбра не попадают в БД и в evidence")
    func unresolvedIsNotPersisted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-codeindex-t2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { cleanup(root) }
        try write("func draw() {\n    missingHelper()\n}", "Sources/Caller.swift", in: root)

        let fileRecords = records(in: root)
        _ = try CodeIndexService.ensureIndexed(projectPath: root.path, records: fileRecords)

        let store = try CodeIndexStore.open(projectPath: root.path)
        let drawID = CodeSymbol.makeID(
            path: "Sources/Caller.swift", kind: "func", name: "draw", startLine: 1
        )
        let stored = try store.edges(touching: [drawID], includeUnresolved: true)
        #expect(!stored.contains { $0.to.hasPrefix("unresolved:") })
        #expect(stored.contains { $0.kind == .declares })
    }

    // MARK: - T3: search with graph neighbors

    @Test("T3: code_search возвращает источник, точный диапазон и соседей по графу")
    func searchReturnsSourceAndNeighbors() throws {
        let root = try makeProject()
        defer { cleanup(root) }
        let fileRecords = records(in: root)

        let hits = try CodeIndexService.search(
            projectPath: root.path,
            query: "load",
            records: fileRecords
        )
        let load = try #require(hits.first?.symbol)
        #expect(load.name == "load")
        #expect(load.path == "Sources/UserStore.swift")
        #expect(load.startLine == 6)
        #expect(load.endLine == 8)

        let neighbors = try #require(hits.first?.neighbors)
        // `reload` is itself a hit (name contains "load"); it must still be
        // shown as the caller of `load` instead of being subtracted away.
        #expect(neighbors.contains {
            $0.edge == .calls && !$0.isOutgoing && $0.name == "reload" && $0.confidence == .exact
        })
        #expect(neighbors.contains {
            $0.edge == .declares && !$0.isOutgoing && $0.kind == "file"
        })

        let rendered = CodeIndexService.renderSearch(query: "load", hits: hits)
        #expect(rendered.contains("Sources/UserStore.swift:6-8 func load"))
        #expect(rendered.contains("id: \(load.id)"))
        #expect(rendered.contains("[exact]"))
    }

    // MARK: - T4: read_symbol

    @Test("T4: read_symbol возвращает точный диапазон с номерами строк и проверенным hash")
    func readSymbolReturnsExactLines() throws {
        let root = try makeProject()
        defer { cleanup(root) }
        let fileRecords = records(in: root)
        let hits = try CodeIndexService.search(
            projectPath: root.path, query: "load", records: fileRecords
        )
        let load = try #require(hits.first?.symbol)
        let storedHash = try #require(
            fileRecords.first { $0.path == "Sources/UserStore.swift" }?.hash
        )

        let body = try CodeIndexService.readSymbol(projectPath: root.path, id: load.id)
        #expect(body.symbol == load)
        #expect(body.verifiedHash == storedHash)
        #expect(body.text.hasPrefix("6\t    func load(id: String) -> Int {"))
        #expect(body.text.contains("7\t        cache[id] ?? 0"))
        #expect(body.text.hasSuffix("8\t    }"))

        let byName = try CodeIndexService.readSymbol(
            projectPath: root.path,
            path: "Sources/UserStore.swift",
            name: "load"
        )
        #expect(byName.symbol == load)
        #expect(byName.text == body.text)
    }

    @Test("T4: изменённый файл не отдаёт старые номера строк, а повторный поиск лечит индекс")
    func changedFileIsRefusedThenReindexed() throws {
        let root = try makeProject()
        defer { cleanup(root) }
        let fileRecords = records(in: root)
        let hits = try CodeIndexService.search(
            projectPath: root.path, query: "load", records: fileRecords
        )
        let load = try #require(hits.first?.symbol)

        let changed = userStoreSource.replacingOccurrences(of: "cache[id] ?? 0", with: "cache[id] ?? 1")
        try write(changed, "Sources/UserStore.swift", in: root)

        #expect(throws: CodeIndexError.self) {
            _ = try CodeIndexService.readSymbol(projectPath: root.path, id: load.id)
        }

        // Fresh records re-index the file from disk; the same symbol id now
        // returns the new body instead of a wrong line range.
        let fresh = records(in: root)
        let healed = try CodeIndexService.search(
            projectPath: root.path, query: "load", records: fresh
        )
        #expect(healed.contains { $0.symbol.id == load.id })
        let body = try CodeIndexService.readSymbol(projectPath: root.path, id: load.id)
        #expect(body.text.contains("?? 1"))
        #expect(body.verifiedHash == fresh.first { $0.path == "Sources/UserStore.swift" }?.hash)
    }

    // MARK: - T5: incremental index and stale marking

    @Test("T5: индекс инкрементален по hash/mtime и помечает пропавшие файлы stale")
    func incrementalIndexAndStale() throws {
        let root = try makeProject()
        defer { cleanup(root) }

        let first = try CodeIndexService.ensureIndexed(
            projectPath: root.path, records: records(in: root)
        )
        #expect(first.parsed == 3)
        #expect(first.unchanged == 0)

        let second = try CodeIndexService.ensureIndexed(
            projectPath: root.path, records: records(in: root)
        )
        #expect(second.parsed == 0)
        #expect(second.unchanged == 3)
        #expect(second.counts.files == 3)

        // Same content, touched file: no re-parse, timestamp refreshed.
        let storeURL = root.appendingPathComponent("Sources/UserStore.swift")
        let touchedAt = Date().addingTimeInterval(30)
        try FileManager.default.setAttributes(
            [.modificationDate: touchedAt], ofItemAtPath: storeURL.path
        )
        let touchedRecords = records(in: root)
        let touched = try CodeIndexService.ensureIndexed(
            projectPath: root.path, records: touchedRecords
        )
        #expect(touched.parsed == 0)
        #expect(touched.unchanged == 3)
        let store = try CodeIndexStore.open(projectPath: root.path)
        let recordMTime = try #require(
            touchedRecords.first { $0.path == "Sources/UserStore.swift" }?.lastModified
        )
        #expect(abs((try store.fileState(path: "Sources/UserStore.swift")?.mtime ?? 0) - recordMTime) < 0.001)

        // A changed file is the only one re-parsed.
        try write(userStoreSource + "\n\nfunc extra() {}\n", "Sources/UserStore.swift", in: root)
        let changed = try CodeIndexService.ensureIndexed(
            projectPath: root.path, records: records(in: root)
        )
        #expect(changed.parsed == 1)
        #expect(changed.unchanged == 2)

        // A deleted file is marked stale and disappears from search.
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/App.swift"))
        let afterDelete = records(in: root)
        let deleted = try CodeIndexService.ensureIndexed(
            projectPath: root.path, records: afterDelete
        )
        #expect(deleted.stale == 1)
        #expect(try store.fileState(path: "Sources/App.swift")?.isStale == true)
        let bootHits = try CodeIndexService.search(
            projectPath: root.path, query: "bootstrap", records: afterDelete
        )
        #expect(bootHits.isEmpty)
    }

    // MARK: - T6: separate database

    @Test("T6: граф живёт в .mycoder/code_index.sqlite, project.db не создаётся")
    func graphUsesItsOwnDatabase() throws {
        let root = try makeProject()
        defer { cleanup(root) }
        _ = try CodeIndexService.ensureIndexed(projectPath: root.path, records: records(in: root))

        let indexURL = CodeIndexStore.databaseURL(projectPath: root.path)
        #expect(indexURL.lastPathComponent == "code_index.sqlite")
        #expect(FileManager.default.fileExists(atPath: indexURL.path))

        let projectDB = ProjectDatabaseLocator.databaseURL(projectPath: root.path)
        #expect(!FileManager.default.fileExists(atPath: projectDB.path))

        let store = try CodeIndexStore.open(projectPath: root.path)
        let counts = try store.counts()
        #expect(counts.files == 3)
        #expect(counts.symbols > 0)
        #expect(counts.edges > 0)
    }

    // MARK: - T7: tools

    @Test("T7: code_search/read_symbol зарегистрированы, read-only и реально исполняются")
    func toolsAreWired() async throws {
        #expect(WebEmulatedTool.codeSearch.rawValue == "code_search")
        #expect(WebEmulatedTool.readSymbol.rawValue == "read_symbol")
        #expect(HarnessProfile.standard.tools.contains(.codeSearch))
        #expect(HarnessProfile.standard.tools.contains(.readSymbol))
        #expect(SubagentRunner.readOnlyTools.contains("code_search"))
        #expect(SubagentRunner.readOnlyTools.contains("read_symbol"))

        #expect(WebToolAccessGate.permission(
            for: WebToolCall(name: "code_search", arguments: ["query": "load"]),
            accessLevel: .askBeforeChanges
        ) == .allow)
        #expect(WebToolAccessGate.permission(
            for: WebToolCall(name: "read_symbol", arguments: ["id": "x"]),
            accessLevel: .askBeforeChanges
        ) == .allow)

        let root = try makeProject()
        defer { cleanup(root) }
        let executor = ProjectWebToolExecutor(
            projectRoot: root.path,
            accessLevel: .askBeforeChanges
        )

        let search = await executor.execute(WebToolCall(
            name: "code_search",
            arguments: ["query": "load"]
        ))
        #expect(search.contains("func load"))
        #expect(search.contains("id: symbol:Sources/UserStore.swift#func:load@6"))

        let read = await executor.execute(WebToolCall(
            name: "read_symbol",
            arguments: ["path": "Sources/UserStore.swift", "name": "load"]
        ))
        #expect(read.contains("hash verified"))
        #expect(read.contains("6\t    func load(id: String) -> Int {"))

        let definition = MyCoderAutoFreeClient.toolDefinition(for: .codeSearch)
        #expect(definition.function.parameters.required == ["query"])
        #expect(definition.function.parameters.properties["query"] != nil)
        #expect(MyCoderAutoFreeClient.agentToolDefinitions().contains {
            $0.function.name == "code_search"
        })
    }
}
