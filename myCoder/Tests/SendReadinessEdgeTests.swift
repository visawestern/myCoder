import Testing
@testable import myCoder

@Suite("Send readiness edge cases")
struct SendReadinessEdgeTests {
    @Test("whitespace-only provider IDs are rejected even when Serve is connected")
    func whitespaceProviderIsRejected() {
        #expect(SendProviderReadinessLogic.connectionValidationError(
            serverConnected: true,
            selectedProviderID: "   \n",
            autoFreeReady: true,
            customProviders: [],
            localProviderIDs: [],
            webProviderIDs: [],
            serverProviderIDs: [],
            webConnected: nil
        ) != nil)
    }
}
