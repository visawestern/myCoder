import Foundation

enum WebCaptchaResolutionAction: Equatable {
    case wait
    case resume
    case abort
}

enum WebCaptchaResolutionLogic {
    static func action(for state: WebSessionState) -> WebCaptchaResolutionAction {
        switch state {
        case .captchaRequired:
            return .wait
        case .connected:
            return .resume
        case .loggedOut:
            return .abort
        case .limitReached:
            // A quota/paywall page never resolves by waiting — abort the
            // turn with an honest error instead of polling it.
            return .abort
        case .unknown:
            return .wait
        }
    }
}
