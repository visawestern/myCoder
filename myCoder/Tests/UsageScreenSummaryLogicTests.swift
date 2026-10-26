import Foundation
import Testing
@testable import myCoder

@Suite("USG-02 usage screen summary")
struct UsageScreenSummaryLogicTests {
    @Test("message count follows the selected usage points")
    func messageCountUsesFilteredPoints() {
        let points = [
            UsageDataPoint(
                timestamp: Date(timeIntervalSince1970: 1),
                model: "gpt-4o",
                provider: "openai",
                promptTokens: 10,
                completionTokens: 5,
                costUSD: 0.01
            ),
            UsageDataPoint(
                timestamp: Date(timeIntervalSince1970: 2),
                model: "gpt-4o",
                provider: "openai",
                promptTokens: 20,
                completionTokens: 10,
                costUSD: 0.02
            )
        ]
        #expect(UsageScreenSummaryLogic.messageCount(for: points) == 2)
    }

    @Test("empty selected usage period reports zero messages")
    func emptyPeriodReportsZero() {
        #expect(UsageScreenSummaryLogic.messageCount(for: []) == 0)
    }
}
