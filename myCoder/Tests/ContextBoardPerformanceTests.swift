import Testing
import Foundation
@testable import myCoder

/// Performance guard for the context board. On a real project the board is
/// rebuilt on every preview and every send, so a byte-level helper that
/// allocates on each character turns a 12 MB index into a multi-minute stall.
/// The limits here are deliberately generous (an order of magnitude above the
/// intended cost) — they catch accidental quadratic work, not machine noise.
@MainActor
@Suite("Context board performance")
struct ContextBoardPerformanceTests {

    /// Release is the shipped configuration; debug builds are 4-10x slower
    /// because every byte loop keeps bounds checks and no inlining. Keeping
    /// one absolute number would either flake in debug or stop guarding
    /// release.
    private var debugFactor: Double {
        #if DEBUG
        return 6.0
        #else
        return 1.0
        #endif
    }

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

    @Test("Masking a large source file stays linear")
    func maskingLargeSourceIsFast() {
        // ~700 KB: strings and comments force the masking walk on every byte.
        var text = ""
        text.reserveCapacity(750_000)
        for index in 0..<7_000 {
            text += "struct Demo\(index) { let value: Int; func run() { print(\"hello // not a comment\") } }\n"
            text += "// комментарий \(index): строка не должна стать объявлением\n"
        }
        let started = Date()
        _ = SymbolNameExtractor.maskedText(text, language: "swift")
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 0.25 * debugFactor, "masking 700 KB took \(elapsed)s")
    }

    @Test("A two-megabyte source file does not dominate a send")
    func twoMegabyteFileIsFast() {
        var text = ""
        text.reserveCapacity(2_100_000)
        for index in 0..<20_000 {
            text += "struct Big\(index) { let value: Int; func run() { print(\"big \(index)\") } }\n"
        }
        let started = Date()
        let board = ContextBoardBuilder.build(
            projectPath: "/tmp/perf",
            records: [record(path: "Sources/Big.swift", text: text)]
        )
        let elapsed = Date().timeIntervalSince(started)
        #expect(board.entries.count == 1)
        #expect(elapsed < 1.0 * debugFactor, "building a 2 MB file took \(elapsed)s")
    }

    @Test("A thousand small files build a board quickly")
    func manySmallFilesAreFast() {
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
        #expect(elapsed < 1.5 * debugFactor, "building 1000 files took \(elapsed)s")
    }
}
