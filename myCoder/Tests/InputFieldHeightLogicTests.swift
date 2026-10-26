import Testing
@testable import myCoder

@Suite("Input field height")
struct InputFieldHeightLogicTests {

    @Test("Empty text uses minimum height")
    func emptyUsesMin() {
        let height = InputFieldHeightLogic.preferredHeight(
            text: "",
            fontSize: 14,
            minHeight: 24,
            maxHeight: 72
        )
        #expect(height == 24)
    }

    @Test("Multi-line text grows up to cap")
    func multiLineGrows() {
        let text = "line one\nline two\nline three\nline four\nline five"
        let height = InputFieldHeightLogic.preferredHeight(
            text: text,
            fontSize: 14,
            minHeight: 24,
            maxHeight: 72
        )
        #expect(height == 72)
    }
}
