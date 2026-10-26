import Foundation

/// Chooses where the chat-loading spinner appears. During a session switch the
/// store is cleared first, so the spinner belongs in the empty chat body; a
/// same-session refresh keeps the rows and gets a slim inline indicator.
enum ChatLoadingIndicatorLogic {
    enum Presentation: Equatable {
        case hidden
        case centered
        case inline
    }

    static func presentation(isLoading: Bool,
                             messageCount: Int) -> Presentation {
        guard isLoading else { return .hidden }
        return messageCount == 0 ? .centered : .inline
    }
}
