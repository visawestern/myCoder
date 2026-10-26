import Foundation

enum WebSendCompletionLogic {
    static func recordsCompletion(for event: WebChatEvent) -> Bool {
        switch event {
        case .final(let text):
            return ProviderResponseValidationLogic.hasVisibleContent(text)
        case .error:
            // Audit 2026-09-09: a turn that concluded with an HONEST error
            // (e.g. the vendor failed generation twice) is complete — the
            // bubble already carries the error text. Without this the caller
            // appends a second misleading "did not produce a verified final
            // answer" line after the real error.
            return true
        default:
            return false
        }
    }
}
