import Foundation

enum WebLoginCaptureLogic {
    static func canPersist(cookieCount: Int) -> Bool {
        cookieCount > 0
    }

    static func captureMessage(cookieCount: Int) -> String {
        canPersist(cookieCount: cookieCount)
            ? "Session captured."
            : "No authenticated cookies were found. Log in before capturing the session."
    }

    static func shouldActivateSession(cookieCount: Int, persistenceSucceeded: Bool) -> Bool {
        canPersist(cookieCount: cookieCount) && persistenceSucceeded
    }
}
