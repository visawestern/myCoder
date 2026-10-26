import Foundation

enum SendButtonActivationLogic {
    /// The composer action stays available while a turn is running: the
    /// message is queued instead of sent immediately (user directive: extra
    /// messages must be enqueueable while the model is busy).
    static func canInvokeSend(canSend: Bool, isLoading: Bool) -> Bool {
        canSend
    }

    /// A queued message may be forced out while the current turn runs.
    static func canInvokeQueue(canSend: Bool, isLoading: Bool) -> Bool {
        canSend || isLoading
    }
}
