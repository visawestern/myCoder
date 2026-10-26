import Foundation
import Testing
@testable import myCoder

@Suite("WEB-LOGIN-11: capture session guard")
struct WebLoginCaptureLogicTests {
    @Test("empty cookie snapshot cannot be captured as a login")
    func emptyCookiesAreRejected() {
        #expect(!WebLoginCaptureLogic.canPersist(cookieCount: 0))
    }

    @Test("non-empty cookie snapshot can be persisted")
    func nonEmptyCookiesAreAccepted() {
        #expect(WebLoginCaptureLogic.canPersist(cookieCount: 2))
    }

    @Test("capture status explains missing authentication")
    func missingCookieMessageIsActionable() {
        #expect(WebLoginCaptureLogic.captureMessage(cookieCount: 0) == "No authenticated cookies were found. Log in before capturing the session.")
        #expect(WebLoginCaptureLogic.captureMessage(cookieCount: 1) == "Session captured.")
    }

    @Test("failed persistence cannot activate a web session")
    func persistenceFailureDoesNotActivate() {
        #expect(!WebLoginCaptureLogic.shouldActivateSession(cookieCount: 2, persistenceSucceeded: false))
        #expect(WebLoginCaptureLogic.shouldActivateSession(cookieCount: 2, persistenceSucceeded: true))
        #expect(!WebLoginCaptureLogic.shouldActivateSession(cookieCount: 0, persistenceSucceeded: true))
    }
}
