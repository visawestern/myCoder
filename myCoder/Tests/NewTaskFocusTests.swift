import Testing
import Foundation
@testable import myCoder

@Suite("New Task Input Focus")
struct NewTaskFocusTests {

    @Test("startNewTask requests input focus")
    @MainActor
    func startNewTaskRequestsFocus() {
        let state = AppState()
        let before = state.inputFocusRequest
        state.startNewTask()
        #expect(state.inputFocusRequest == before + 1)
        state.startNewTask()
        #expect(state.inputFocusRequest == before + 2)
    }

    @Test("Empty-state prompt consumes the focus request")
    func promptFieldConsumesFocusRequest() throws {
        let inputViews = try sourceText("myCoder/Sources/Views/Components/InputViews.swift")
        #expect(inputViews.contains("focusRequest: appState.inputFocusRequest"))

        let zeroInset = try sourceText("myCoder/Sources/Views/Components/ZeroInsetTextField.swift")
        #expect(zeroInset.contains("focusRequest"))
        #expect(zeroInset.contains("makeFirstResponder"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try RepoRoot.sourceText(relativePath)
    }
}
