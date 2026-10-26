import Testing
import Foundation
@testable import myCoder

@Suite("UsageCapture helpers isZero / hasCost (round 2)")
struct UsageCaptureHelpersTests {

    @Test func hasCostTrueWhenCostPresent() {
        let c = UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: 0.001, modelID: "m", providerID: "p")
        #expect(c.hasCost == true)
    }

    @Test func hasCostFalseWhenNil() {
        let c = UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: nil, modelID: "m", providerID: "p")
        #expect(c.hasCost == false)
    }

    @Test func hasCostTrueWhenZero() {
        let c = UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: 0.0, modelID: "m", providerID: "p")
        #expect(c.hasCost == true)
    }

    @Test func isZeroWhenBothTokensZero() {
        let c = UsageCapture(promptTokens: 0, completionTokens: 0, costUSD: nil, modelID: "m", providerID: "p")
        #expect(c.isZero == true)
    }

    @Test func isZeroFalseWhenAnyTokenPresent() {
        let onlyPrompt = UsageCapture(promptTokens: 5, completionTokens: 0, costUSD: nil, modelID: "m", providerID: "p")
        let onlyCompletion = UsageCapture(promptTokens: 0, completionTokens: 5, costUSD: nil, modelID: "m", providerID: "p")
        #expect(onlyPrompt.isZero == false)
        #expect(onlyCompletion.isZero == false)
    }

    @Test func isZeroIgnoresCost() {
        let c = UsageCapture(promptTokens: 0, completionTokens: 0, costUSD: 1.5, modelID: "m", providerID: "p")
        #expect(c.isZero == true)
    }
}
