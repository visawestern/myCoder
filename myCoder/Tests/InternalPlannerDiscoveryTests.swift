import Foundation
import Testing
@testable import myCoder

@MainActor
@Suite("Internal planner semantic discovery")
struct InternalPlannerDiscoveryTests {
    private func board(paths: [String]) -> ContextBoard {
        let records = paths.enumerated().map { index, path in
            let source = """
            struct FrameStore\(index) {
                func persistFrames\(index)() {}
            }
            """
            return FileIndexRecord(path: path, hash: "h\(index)", size: source.utf8.count,
                                   lastModified: Double(index), language: "swift", searchableText: source)
        }
        return ContextBoardBuilder.build(projectPath: "/tmp/discovery", records: records)
    }

    @Test func russianRequestGetsBoundedRealDirectoryWhenLexicalSearchMisses() throws {
        let sourceBoard = board(paths: ["Sources/FrameStorage.swift", "Views/ExportSettings.swift"])
        let context = LocalPlannerContextBuilder.build(
            message: "кадры теперь в оперативной памяти, проверь последствия", board: sourceBoard, memories: []
        )
        #expect(context.files == ["Sources/FrameStorage.swift", "Views/ExportSettings.swift"])
        #expect(context.symbolNames.contains("persistFrames0"))
        let parsed = try LocalQueryPlanParser.parse(#"{"files":["Sources/FrameStorage.swift"],"symbols":["persistFrames0"]}"#)
        let resolved = LocalQueryPlanParser.resolve(parsed, context: context)
        #expect(resolved.plan.files == ["Sources/FrameStorage.swift"])
        #expect(resolved.plan.symbols == ["persistFrames0"])
        #expect(resolved.dropped.isEmpty)
    }

    @Test func discoveryDirectoryIsStableBoundedAndKeepsSecretsOut() {
        let paths = (0..<90).map { "Sources/F\(String(format: "%03d", $0)).swift" }
        let sourceBoard = board(paths: paths + [".env", "private.key"])
        let context = LocalPlannerContextBuilder.build(message: "исследуй зависимости", board: sourceBoard, memories: [])
        let reverseBoard = ContextBoard(projectPath: sourceBoard.projectPath, entries: Array(sourceBoard.entries.reversed()), builtAt: sourceBoard.builtAt)
        let reverse = LocalPlannerContextBuilder.build(message: "исследуй зависимости", board: reverseBoard, memories: [])
        #expect(context == reverse)
        #expect(context.files.count == 64)
        #expect(context.taskContext.contains("64 из 90"))
        #expect(context.files.first == "Sources/F000.swift")
        #expect(!context.files.contains(".env"))
        #expect(!context.files.contains("private.key"))
        #expect(context.symbolNames.count <= 64 * LocalPlannerContextBuilder.maxSymbolsPerFile)
    }

    @Test func fileNameMatchIncludesItsDeclaredSymbols() {
        let sourceBoard = board(paths: ["Sources/FrameStorage.swift"])
        let context = LocalPlannerContextBuilder.build(message: "FrameStorage", board: sourceBoard, memories: [])
        #expect(context.files == ["Sources/FrameStorage.swift"])
        #expect(context.symbolNames.contains("persistFrames0"))
    }

    @Test func explicitRankedMatchesStillRespectTopK() {
        let sourceBoard = board(paths: ["Sources/FrameStorage.swift", "Views/ExportSettings.swift"])
        let context = LocalPlannerContextBuilder.build(message: "persistFrames1", board: sourceBoard, memories: [], maxFiles: 1)
        #expect(context.files == ["Views/ExportSettings.swift"])
    }
}
