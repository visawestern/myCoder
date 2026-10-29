import Foundation

/// One row of the interview screen, top to bottom.
enum SpecWizardInterviewBlock: Hashable {
    /// The live question with its answer controls.
    case question
    /// The collected interview when it is complete.
    case summary
    /// The transcript of answered exchanges, newest first.
    case feed
}

enum SpecWizardInterviewLayoutLogic {
    /// The live question (or the completion summary) is always on top: the user
    /// must never scroll past the history to answer. The feed follows it with
    /// the answered exchanges in reverse chronological order, so the question
    /// the user just answered is the first row of the list (user directive
    /// 2026-10-28), not the last one.
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

    /// Reorder a chronological transcript so the newest exchange comes first.
    ///
    /// A planner turn opens an exchange and the user turn(s) that follow it are
    /// its answer; chunks are reversed but kept internally in reading order, so
    /// every block still reads "question, then answer". Turns that do not start
    /// with a planner row are preserved as their own chunk.
    static func newestFirst(_ turns: [SpecPlannerTurn]) -> [SpecPlannerTurn] {
        var chunks: [[SpecPlannerTurn]] = []
        for turn in turns {
            if turn.role == "planner" || chunks.isEmpty {
                chunks.append([turn])
            } else {
                chunks[chunks.count - 1].append(turn)
            }
        }
        return chunks.reversed().flatMap { $0 }
    }

    /// Drop the live question from the transcript while its answer card is on
    /// screen, so the same question is never rendered twice (the card owns it).
    static func history(_ turns: [SpecPlannerTurn], excludingLiveQuestion: Bool) -> [SpecPlannerTurn] {
        guard excludingLiveQuestion,
              let index = turns.lastIndex(where: { $0.role == "planner" }) else {
            return turns
        }
        var copy = turns
        copy.remove(at: index)
        return copy
    }
}
