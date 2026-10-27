import Foundation

/// One row of the interview screen, top to bottom.
enum SpecWizardInterviewBlock: Hashable {
    /// The live question with its answer controls.
    case question
    /// The collected interview when it is complete.
    case summary
    /// The transcript of every turn, oldest first.
    case feed
}

enum SpecWizardInterviewLayoutLogic {
    /// The live question (or the completion summary) is always on top: the user
    /// must never scroll past the history to answer. The feed always closes the
    /// screen and grows downward — oldest turn first, newest last.
    ///
    /// An answered question is hidden (`isQuestionCardVisible == false`) but its
    /// turns stay in the feed, so nothing the user typed disappears.
    static func blocks(
        hasQuestion: Bool,
        isQuestionCardVisible: Bool,
        hasCompletedSummary: Bool,
        interviewComplete: Bool
    ) -> [SpecWizardInterviewBlock] {
        if hasQuestion && isQuestionCardVisible {
            return [.question, .feed]
        }
        if hasCompletedSummary && interviewComplete {
            return [.summary, .feed]
        }
        return [.feed]
    }
}
