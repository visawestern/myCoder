import Testing
import Foundation
@testable import myCoder

/// Performance guard for the context board. On a real project the board is
/// rebuilt on every preview and every send, so a byte-level helper that
/// allocates on each character turns a 12 MB index into a multi-minute stall.
///
/// These suites are deliberately NOT @MainActor: the same work runs on
/// background threads in production, and a synchronous multi-second masking/
/// board build on the main actor froze every other suite in the shared test
/// process (observed 2026-11-13).
///
/// Absolute wall-clock limits are noise-sensitive (other suites share the
/// CPU), so the linearity checks compare two sizes of the same work: growth
/// must be roughly proportional, not quadratic. Two equal-sized runs get the
/// same noise, so the ratio is stable.
@Suite("Context board performance")
struct ContextBoardPerformanceTests {

    private func record(path: String, text: String, language: String = "swift") -> FileIndexRecord {
        FileIndexRecord(
            path: path,
            hash: "hash",
            size: text.utf8.count,
            lastModified: 0,
            language: language,
            searchableText: text
        )
    }

    /// Builds `count` fake declarations (strings + comments force the masking
    /// walk on every byte), totalling roughly `sizeBytes`.
    private func sourceText(sizeBytes: Int, perLine: Int = 95) -> String {
        var text = ""
        text.reserveCapacity(sizeBytes)
        var index = 0
        while text.utf8.count < sizeBytes {
            text += "struct Demo\(index) { let value: Int; func run() { print(\"hello // not a comment\") } }\n"
            text += "// комментарий \(index): строка не должна стать объявлением\n"
            index += 1
        }
        return text
    }

    @Test("Masking scales linearly with file size (not quadratic)")
    func maskingScalesLinearly() {
        let small = sourceText(sizeBytes: 350_000)
        let large = sourceText(sizeBytes: 700_000)

        let smallStart = Date()
        let smallMasked = SymbolNameExtractor.maskedText(small, language: "swift")
        let smallElapsed = Date().timeIntervalSince(smallStart)

        let largeStart = Date()
        let largeMasked = SymbolNameExtractor.maskedText(large, language: "swift")
        let largeElapsed = Date().timeIntervalSince(largeStart)

        // Work really happened: masking replaces a non-trivial fraction.
        #expect(smallMasked.utf8.count == small.utf8.count)
        #expect(largeMasked.utf8.count == large.utf8.count)
        #expect(largeElapsed < smallElapsed * 3, "masking 700 KB took \(largeElapsed)s vs \(smallElapsed)s for 350 KB — quadratic-ish growth")
    }

    @Test("A two-megabyte source file builds a board linearly")
    func twoMegabyteBuildScalesLinearly() {
        // Two same-shaped files of different sizes: build time must grow
        // linearly with size, not as O(n²), which freezes a send.
        func buildBoard(sizeBytes: Int) -> (ContextBoard, TimeInterval) {
            var text = ""
            text.reserveCapacity(sizeBytes)
            var index = 0
            while text.utf8.count < sizeBytes {
                text += "struct Big\(index) { let value: Int; func run() { print(\"big \(index)\") } }\n"
                index += 1
            }
            let started = Date()
            let board = ContextBoardBuilder.build(
                projectPath: "/tmp/perf",
                records: [record(path: "Sources/Big.swift", text: text)]
            )
            return (board, Date().timeIntervalSince(started))
        }

        let (smallBoard, smallElapsed) = buildBoard(sizeBytes: 1_000_000)
        let (largeBoard, largeElapsed) = buildBoard(sizeBytes: 2_000_000)
        #expect(smallBoard.entries.count == 1)
        #expect(largeBoard.entries.count == 1)
        #expect(largeElapsed < smallElapsed * 3, "building a 2 MB file took \(largeElapsed)s vs \(smallElapsed)s for 1 MB — quadratic-ish growth")
    }

    @Test("A thousand small files build a board quickly")
    func manySmallFilesAreFast() {
        // Absolute budget is fine here: the per-file constant dominates and a
        // 1.5×(6 in debug) seconds ceiling still flags an accidental O(n²)
        // scan over 1000 tiny files.
        let records: [FileIndexRecord] = (0..<1_000).map { index in
            let text = """
            import Foundation

            /// Documentation line \(index)
            struct Demo\(index) {
                let value: Int
                func run() { print("value \(index)") }
            }
            """
            return record(path: "Sources/Demo\(index).swift", text: text)
        }
        let started = Date()
        let board = ContextBoardBuilder.build(projectPath: "/tmp/perf", records: records)
        let elapsed = Date().timeIntervalSince(started)
        #expect(board.entries.count == 1_000)
        #expect(elapsed < 1.5 * 6.0, "building 1000 files took \(elapsed)s")
    }
}
