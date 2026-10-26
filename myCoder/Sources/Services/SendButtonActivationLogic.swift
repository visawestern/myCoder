import Foundation

enum SendButtonActivationLogic {
    static func canInvokeSend(canSend: Bool, isLoading: Bool) -> Bool {
        canSend && !isLoading
    }
}
