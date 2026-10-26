import Foundation
import Testing
@testable import myCoder

@Suite("USG-02/USG-03 usage token safety")
struct UsageTokenSafetyTests {
    @Test("UsageCapture clamps negative provider token counts")
    func captureClampsNegativeTokens() {
        let capture = UsageCapture(
            promptTokens: -10,
            completionTokens: 7,
            costUSD: 0.01,
            modelID: "model",
            providerID: "provider"
        )
        #expect(capture.promptTokens == 0)
        #expect(capture.completionTokens == 7)
        #expect(capture.totalTokens == 7)
        #expect(!capture.isZero)
    }

    @Test("UsageDataPoint clamps negative persisted token counts")
    func dataPointClampsNegativeTokens() {
        let point = UsageDataPoint(
            timestamp: Date(),
            model: "model",
            provider: "provider",
            promptTokens: 4,
            completionTokens: -3,
            costUSD: nil
        )
        #expect(point.promptTokens == 4)
        #expect(point.completionTokens == 0)
        #expect(point.totalTokens == 4)
    }
}
