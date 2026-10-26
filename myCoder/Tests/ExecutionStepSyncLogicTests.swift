import Testing
@testable import myCoder

@Suite("Execution step sync")
struct ExecutionStepSyncLogicTests {

    @Test("Builds in-progress and completed steps from markers")
    func syncFromMarkers() {
        let parts: [MessagePartContent] = [
            .stepStart,
            .stepFinish,
            .stepStart
        ]
        let steps = ExecutionStepSyncLogic.steps(from: parts)
        #expect(steps.count == 2)
        #expect(steps[0].status == .completed)
        #expect(steps[1].status == .inProgress)
    }
}
