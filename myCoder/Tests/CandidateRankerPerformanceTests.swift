import Testing
import Foundation
@testable import myCoder

/// `CandidateRanker.rank` was the single hottest frame in a live send
/// (567 of 1869 samples, on the main thread): for every file it walked every
/// query term against every symbol, and `ContextBoardBuilder.tokens` rebuilt a
/// `Set<String>` from `unicodeScalars` for every file on every send. A send
/// that should take a second stalled long enough that the turn never answered
/// (live run 2026-11-04, chat 77DF9308).
///
/// These are guardrails, not micro-benchmarks: they fail when the ranking
/// becomes superlinear in files × terms again.
@MainActor
@Suite("Скорость отбора кандидатов")
struct CandidateRankerPerformanceTests {

    private func makeBoard(files: Int, symbolsPerFile: Int) -> ContextBoard {
        let entries: [ContextBoardEntry] = (0..<files).map { i in
            let symbols = (0..<symbolsPerFile).map { s in
                SymbolDeclaration(name: "symbol\(i)_\(s)", kind: "func", line: s + 1)
            }
            return ContextBoardEntry(
                path: "src/module\(i)/file\(i).swift",
                language: "swift",
                size: 4_000,
                lastModified: Double(i),
                symbols: symbols,
                imports: [],
                doc: nil,
                searchTokens: ["token\(i)", "shared", "context"]
            )
        }
        return ContextBoard(projectPath: "/tmp/proj", entries: entries, builtAt: Date())
    }

    @Test("Ранжирование 2000 файлов укладывается в секунду")
    func rankingLargeBoardIsFast() {
        let board = makeBoard(files: 2_000, symbolsPerFile: 60)
        let query = "context compiler symbol12_3 token7"
        let started = Date()
        let result = CandidateRanker.rank(board: board, query: query)
        let elapsed = Date().timeIntervalSince(started)
        #expect(!result.isEmpty)
        #expect(elapsed < 1.0, "ранжирование заняло \(elapsed) c — снова квадратично")
    }

    @Test("Ранжирование не зависит от размера доски квадратично")
    func rankingScalesLinearly() {
        let small = makeBoard(files: 500, symbolsPerFile: 40)
        let large = makeBoard(files: 2_000, symbolsPerFile: 40)
        let query = "context compiler token7"

        let t0 = Date()
        _ = CandidateRanker.rank(board: small, query: query)
        let smallTime = Date().timeIntervalSince(t0)

        let t1 = Date()
        _ = CandidateRanker.rank(board: large, query: query)
        let largeTime = Date().timeIntervalSince(t1)

        // 4x the files must not cost more than ~12x the time (linear + slack).
        let ratio = largeTime / max(smallTime, 0.0005)
        #expect(ratio < 12.0, "рост \(ratio)x на 4x файлов — не линейно")
    }

    @Test("Токенизация не квадратична по длине файла")
    func tokensScaleLinearly() {
        // Absolute wall-clock is machine- and load-dependent (a parallel test
        // run doubled it), so compare the same work at two sizes instead.
        let unit = String(repeating: "let contextCompiler = buildContext()\n", count: 500)
        let big = String(repeating: unit, count: 8)

        let t0 = Date()
        for _ in 0..<50 { _ = ContextBoardBuilder.tokens(in: unit) }
        let smallTime = Date().timeIntervalSince(t0)

        let t1 = Date()
        for _ in 0..<50 { _ = ContextBoardBuilder.tokens(in: big) }
        let bigTime = Date().timeIntervalSince(t1)

        // 8x the text must not cost more than ~16x the time.
        let ratio = bigTime / max(smallTime, 0.0005)
        #expect(ratio < 16.0, "рост \(ratio)x на 8x текста — не линейно")
    }

    @Test("Токенизация находит те же идентификаторы, что и раньше")
    func tokensKeepMeaning() {
        let text = "let contextCompiler = buildContext(); // comment\nvar x = 1"
        let tokens = ContextBoardBuilder.tokens(in: text)
        #expect(tokens.contains("contextcompiler"))
        #expect(tokens.contains("buildcontext"))
        #expect(tokens.contains("comment"))
        #expect(!tokens.contains("x"), "однобуквенные не индексируются")
    }

    @Test("Пустой запрос не запускает перебор")
    func emptyQueryIsFree() {
        let board = makeBoard(files: 2_000, symbolsPerFile: 20)
        let started = Date()
        let result = CandidateRanker.rank(board: board, query: "   ")
        let elapsed = Date().timeIntervalSince(started)
        #expect(result.isEmpty)
        #expect(elapsed < 0.1)
    }
}
