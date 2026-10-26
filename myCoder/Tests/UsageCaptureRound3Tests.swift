import Testing
import Foundation
@testable import myCoder

@Suite("ACPUsage -> UsageCapture conversion (round 3)")
struct ACPUsageConversionTests {

    @Test func convertsWithAllTokensPresent() {
        let acp = ACPUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
        let c = UsageCapture(acpUsage: acp, modelID: "gpt-4o", providerID: "openai")
        #expect(c.promptTokens == 100)
        #expect(c.completionTokens == 50)
        #expect(c.modelID == "gpt-4o")
        #expect(c.providerID == "openai")
    }

    @Test func treatsNilTokensAsZero() {
        let acp = ACPUsage(promptTokens: nil, completionTokens: nil, totalTokens: nil)
        let c = UsageCapture(acpUsage: acp, modelID: "m", providerID: "p")
        #expect(c.promptTokens == 0)
        #expect(c.completionTokens == 0)
        #expect(c.isZero == true)
    }

    @Test func partialNilTokensDefaultToZero() {
        let acp = ACPUsage(promptTokens: 42, completionTokens: nil, totalTokens: nil)
        let c = UsageCapture(acpUsage: acp, modelID: "m", providerID: "p")
        #expect(c.promptTokens == 42)
        #expect(c.completionTokens == 0)
    }

    @Test func costIsNilForACP() {
        let acp = ACPUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
        let c = UsageCapture(acpUsage: acp, modelID: "m", providerID: "p")
        #expect(c.costUSD == nil)
        #expect(c.hasCost == false)
    }

    @Test func emptyModelDefaultsToUnknown() {
        let acp = ACPUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2)
        let c = UsageCapture(acpUsage: acp, modelID: "", providerID: "")
        #expect(c.modelID == "unknown")
        #expect(c.providerID == "unknown")
    }
}
