import Testing
@testable import myCoder

@Suite("MODEL-19 Auto Free catalog status")
struct MyCoderAutoFreeCatalogStatusLogicTests {
    @Test("refresh preserves a forced model-switch reason")
    func preservesModelSwitchReason() {
        let previous = "Previously selected model is unavailable; switched to big-pickle."
        let status = MyCoderAutoFreeCatalogStatusLogic.statusAfterRefresh(
            previousStatus: previous,
            previousSelectedModel: "old-model",
            currentSelectedModel: "big-pickle",
            fetchedModelIDs: ["big-pickle", "qwen-free"]
        )
        #expect(status == previous)
    }

    @Test("successful refresh uses ready status when no model was switched")
    func usesReadyStatusWithoutSwitch() {
        #expect(MyCoderAutoFreeCatalogStatusLogic.statusAfterRefresh(
            previousStatus: "Using big-pickle.",
            previousSelectedModel: "big-pickle",
            currentSelectedModel: "big-pickle",
            fetchedModelIDs: ["big-pickle"]
        ) == "Anonymous OpenCode free catalog ready.")
    }
}
