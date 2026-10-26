import Testing
@testable import myCoder

@Suite("Task Header")
struct TaskHeaderTests {

    @Test("Task header should show when session is selected")
    func showsWhenSessionSelected() {
        let state = AppState(host: "127.0.0.1", port: 0)
        #expect(state.selectedSession == nil)
        state.selectedSession = ChatSession(id: "s1", title: "Fix bug")
        #expect(state.selectedSession != nil)
        #expect(TaskHeaderVisibility.shouldShow(selectedSession: state.selectedSession) == true)
    }

    @Test("Task header hidden without session")
    func hiddenWithoutSession() {
        #expect(TaskHeaderVisibility.shouldShow(selectedSession: nil) == false)
    }
}
