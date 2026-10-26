import Foundation
import Testing
@testable import myCoder

@Suite("USG-03 cost provenance safety")
struct UsageCostSafetyTests {
    @Test("negative cost is not shown as a charge")
    func negativeCostBecomesUnavailable() {
        let point = UsageDataPoint(
            timestamp: Date(),
            model: "gpt-4o",
            provider: "openai",
            promptTokens: 10,
            completionTokens: 5,
            costUSD: -0.25
        )
        #expect(point.costUSD == nil)
        #expect(UsageStatisticsAggregator.costLabel(point.costUSD) == "N/A")
    }

    @Test("non-finite cost is not shown as a charge")
    func nonFiniteCostBecomesUnavailable() {
        let point = UsageDataPoint(
            timestamp: Date(),
            model: "gpt-4o",
            provider: "openai",
            promptTokens: 10,
            completionTokens: 5,
            costUSD: .nan
        )
        #expect(point.costUSD == nil)
        #expect(UsageStatisticsAggregator.costLabel(point.costUSD) == "N/A")
    }

    @Test("UsageCapture does not retain invalid provider cost")
    func usageCaptureSanitizesInvalidCost() {
        let capture = UsageCapture(
            promptTokens: 10,
            completionTokens: 5,
            costUSD: -.infinity,
            modelID: "gpt-4o",
            providerID: "openai"
        )
        #expect(capture.costUSD == nil)
    }

    @Test("cost label is defensive for non-finite input")
    func costLabelRejectsNonFiniteInput() {
        #expect(UsageStatisticsAggregator.costLabel(.infinity) == "N/A")
        #expect(UsageStatisticsAggregator.costLabel(-1) == "N/A")
    }

    @Test("zero cost remains a valid reported charge")
    func zeroCostIsPreserved() {
        let point = UsageDataPoint(
            timestamp: Date(),
            model: "free-model",
            provider: "openai",
            promptTokens: 10,
            completionTokens: 5,
            costUSD: 0
        )
        #expect(point.costUSD == 0)
        #expect(UsageStatisticsAggregator.costLabel(point.costUSD) == "$0.00")
    }
}
