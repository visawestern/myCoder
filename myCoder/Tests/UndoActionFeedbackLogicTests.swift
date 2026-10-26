import Testing
@testable import myCoder

@Suite("Undo action feedback")
struct UndoActionFeedbackLogicTests {
    @Test("successful undo reports a clear completion message")
    func successMessage() {
        #expect(UndoActionFeedbackLogic.message(for: .undone) == "Last file change undone.")
    }

    @Test("missing undo entry reports a no-op instead of silence")
    func noOpMessage() {
        #expect(UndoActionFeedbackLogic.message(for: .nothingToUndo) == "Nothing to undo.")
    }

    @Test("undo errors remain visible to the user")
    func failureMessage() {
        #expect(UndoActionFeedbackLogic.message(for: .failed("snapshot missing")) == "Undo failed: snapshot missing")
    }

    @Test("undo outcomes expose an explicit presentation tone")
    func explicitPresentationTone() {
        #expect(UndoActionFeedbackLogic.tone(for: .undone) == .success)
        #expect(UndoActionFeedbackLogic.tone(for: .nothingToUndo) == .warning)
        #expect(UndoActionFeedbackLogic.tone(for: .failed("snapshot missing")) == .error)
    }
}
