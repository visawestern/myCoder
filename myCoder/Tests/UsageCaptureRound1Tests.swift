import Testing
import Foundation
@testable import myCoder

@Suite("UsageCapture — runtime usage value type (round 1)")
struct UsageCaptureTests {

    @Test func constructsWithAllFields() {
        let c = UsageCapture(
            promptTokens: 100,
            completionTokens: 50,
            costUSD: 0.01,
            modelID: "gpt-4o",
            providerID: "openai"
        )
        #expect(c.promptTokens == 100)
        #expect(c.completionTokens == 50)
        #expect(c.costUSD == 0.01)
        #expect(c.modelID == "gpt-4o")
        #expect(c.providerID == "openai")
    }

    @Test func constructsWithNilCostForLocalProvider() {
        let c = UsageCapture(
            promptTokens: 100,
            completionTokens: 50,
            costUSD: nil,
            modelID: "qwen2.5-coder",
            providerID: "ollama"
        )
        #expect(c.costUSD == nil)
    }

    @Test func equatable() {
        let a = UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: 0.001, modelID: "m", providerID: "p")
        let b = UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: 0.001, modelID: "m", providerID: "p")
        let c = UsageCapture(promptTokens: 99, completionTokens: 5, costUSD: 0.001, modelID: "m", providerID: "p")
        #expect(a == b)
        #expect(a != c)
    }

    @Test func distinctByCostNilVsZero() {
        let nilCost = UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: nil, modelID: "m", providerID: "p")
        let zeroCost = UsageCapture(promptTokens: 10, completionTokens: 5, costUSD: 0.0, modelID: "m", providerID: "p")
        #expect(nilCost != zeroCost)
    }
}
