import Testing
@testable import myCoder

@Suite("myCoder Auto Free failover notification reason")
struct MyCoderAutoFreeFailoverLogicTests {
    @Test("HTTP 429 and rate-limit text map to the red rate-limit reason")
    func rateLimitTextUsesRedReason() {
        #expect(MyCoderAutoFreeFailoverLogic.reason(errorDescription: "OpenCode failed (HTTP 429)", failureCount: 1) == "rate limit")
        #expect(MyCoderAutoFreeFailoverLogic.reason(errorDescription: "provider rate limit reached", failureCount: 1) == "rate limit")
    }

    @Test("model and generic failures preserve distinct switch reasons")
    func nonRateLimitReasonsRemainSpecific() {
        #expect(MyCoderAutoFreeFailoverLogic.reason(errorDescription: "model unavailable", failureCount: 1) == "model unavailable")
        #expect(MyCoderAutoFreeFailoverLogic.reason(errorDescription: "HTTP 500", failureCount: 3) == "3 consecutive failures")
    }
}
