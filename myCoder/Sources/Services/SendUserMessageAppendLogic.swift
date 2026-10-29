import Foundation

/// Which user bubble the send path writes for the current turn.
///
/// Force-send used to wait for the interrupted turn to finish before appending
/// anything, so the composer looked like it had lost the message and users
/// re-sent it (the DB showed duplicate user messages on forced turns). The
/// bubble is now shown first and the send path only fills it in.
enum SendUserMessageAppendLogic {

    enum Action: Equatable {
        /// A fresh send: append the user message.
        case appendNew
        /// Force-send already showed the bubble: update it (context parts,
        /// attachments) instead of appending a second copy.
        case updateExisting
        /// A retry reuses the stored turn: nothing to write.
        case skip
    }

    static func action(hasRetryPlan: Bool, existingUserMessageID: String?) -> Action {
        if existingUserMessageID != nil { return .updateExisting }
        if hasRetryPlan { return .skip }
        return .appendNew
    }
}
