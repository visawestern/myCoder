import Foundation
import Testing
@testable import myCoder

@Suite("Round 97 error handling regressions")
struct ErrorHandlingRound97Tests {
    @Test("empty Serve response array becomes actionable empty-response failure")
    func emptyResponseArrayFailsClosed() {
        let message = ServeResponseFeedbackLogic.failureMessage(
            responseCount: 0,
            text: nil,
            reasoning: nil,
            hasToolActivity: false
        )
        #expect(message == ProviderResponseValidationLogic.emptyCompletionMessage)
    }

    @Test("raw Serve transport failure is classified as connection loss")
    func rawTransportFailureIsConnectionLoss() {
        #expect(ServeTransportFailureLogic.isConnectionFailure(URLError(.cannotConnectToHost)))
    }

    @Test("Serve disconnect state is route-scoped and does not poison direct routes")
    func disconnectClassificationIsRouteScoped() {
        let error = URLError(.networkConnectionLost)
        #expect(ServeTransportFailureLogic.shouldMarkServerDisconnected(isServeRoute: true, error: error))
        #expect(!ServeTransportFailureLogic.shouldMarkServerDisconnected(isServeRoute: false, error: error))
    }
}
