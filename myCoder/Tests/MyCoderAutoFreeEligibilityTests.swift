import Testing
@testable import myCoder

@Suite("MODEL-19 Auto Free eligibility")
struct MyCoderAutoFreeEligibilityTests {
    @Test("trusted IDs and any live -free route are eligible, paid IDs are not")
    func freeSuffixEligibility() {
        #expect(MyCoderAutoFreeClient.isEligibleFreeModel("big-pickle"))
        #expect(MyCoderAutoFreeClient.isEligibleFreeModel("mimo-v2.5-free"))
        #expect(MyCoderAutoFreeClient.isEligibleFreeModel("muse-spark-1.3-contributor-free"))
        // Auto-discovery: a future -free route the app has never seen must
        // still be eligible so refresh picks it up without an app update.
        #expect(MyCoderAutoFreeClient.isEligibleFreeModel("untrusted-random-free"))
        // Paid models carry no -free suffix and stay unreachable anonymously.
        #expect(!MyCoderAutoFreeClient.isEligibleFreeModel("claude-opus-5"))
        #expect(!MyCoderAutoFreeClient.isEligibleFreeModel("gpt-5.5"))
        #expect(!MyCoderAutoFreeClient.isEligibleFreeModel("muse-spark-1.2"))
    }
}
