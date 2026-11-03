import Foundation
import Testing
@testable import myCoder

struct ContextFileStageTests {
    @Test func materializationIsTheFinalCollectionStage() {
        let collector = ContextPreviewService.StageCollector()
        _ = TurnContextCompiler.compile(message: "request", board: .init(projectPath: "/tmp/absent", entries: [], builtAt: .distantPast), projectRoot: "/tmp/absent", onStage: { collector.append($0) })
        #expect(collector.stages.last == .files)
    }
}
