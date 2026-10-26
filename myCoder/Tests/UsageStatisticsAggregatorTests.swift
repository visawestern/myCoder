import Testing
import Foundation
@testable import myCoder

@Suite("Usage statistics aggregator (plan Раздел 10)")
struct UsageStatisticsAggregatorTests {

    private func point(_ model: String, provider: String, prompt: Int, completion: Int,
                      cost: Double?, daysAgo: Int = 0) -> UsageDataPoint {
        UsageDataPoint(
            timestamp: Date().addingTimeInterval(-Double(daysAgo) * 86400),
            model: model, provider: provider,
            promptTokens: prompt, completionTokens: completion, costUSD: cost
        )
    }

    @Test func aggregateByModelSumsTokensAndCost() {
        let points = [
            point("gpt-4o", provider: "openai", prompt: 100, completion: 50, cost: 0.01),
            point("gpt-4o", provider: "openai", prompt: 200, completion: 100, cost: 0.02)
        ]
        let aggs = UsageStatisticsAggregator.aggregateByModel(points)
        #expect(aggs.count == 1)
        #expect(aggs.first?.promptTokens == 300)
        #expect(aggs.first?.completionTokens == 150)
        #expect(aggs.first?.totalTokens == 450)
        #expect(aggs.first?.costUSD == 0.03)
    }

    @Test func normalizeMergesModelSnapshots() {
        #expect(UsageStatisticsAggregator.normalizeModelName("gpt-4o-2024-08-06") == "gpt-4o")
        #expect(UsageStatisticsAggregator.normalizeModelName("gpt-4o-20240806") == "gpt-4o")
        #expect(UsageStatisticsAggregator.normalizeModelName("claude-3.5") == "claude-3.5")
    }

    @Test func normalizedAggregationMergesSnapshots() {
        let points = [
            point("gpt-4o-2024-08-06", provider: "openai", prompt: 10, completion: 5, cost: 0.001),
            point("gpt-4o", provider: "openai", prompt: 20, completion: 10, cost: 0.002)
        ]
        let aggs = UsageStatisticsAggregator.aggregateByModel(points, normalize: true)
        #expect(aggs.count == 1)
        #expect(aggs.first?.key == "gpt-4o")
        #expect(aggs.first?.messageCount == 2)
    }

    @Test func localProviderCostIsNilNotZero() {
        let points = [point("qwen2.5-coder", provider: "ollama", prompt: 100, completion: 50, cost: nil)]
        let aggs = UsageStatisticsAggregator.aggregateByModel(points)
        #expect(aggs.first?.costUSD == nil)
        #expect(UsageStatisticsAggregator.costLabel(aggs.first?.costUSD) == "N/A")
    }

    @Test func costLabelFormatsUSD() {
        #expect(UsageStatisticsAggregator.costLabel(1.5) == "$1.50")
        #expect(UsageStatisticsAggregator.costLabel(nil) == "N/A")
    }

    @Test func dateRangeFilters() {
        let points = [
            point("m", provider: "p", prompt: 1, completion: 1, cost: nil, daysAgo: 1),
            point("m", provider: "p", prompt: 1, completion: 1, cost: nil, daysAgo: 40)
        ]
        let filtered = UsageStatisticsAggregator.filter(points, range: .lastDays(7))
        #expect(filtered.count == 1)
    }

    @Test func favoriteModelByUsageNotSelection() {
        let points = [
            point("small", provider: "p", prompt: 10, completion: 10, cost: nil),
            point("big", provider: "p", prompt: 1000, completion: 1000, cost: nil),
            point("big", provider: "p", prompt: 500, completion: 500, cost: nil)
        ]
        #expect(UsageStatisticsAggregator.favoriteModel(points) == "big")
    }

    @Test func activeDaysCountsUniqueDays() {
        let points = [
            point("m", provider: "p", prompt: 1, completion: 1, cost: nil, daysAgo: 0),
            point("m", provider: "p", prompt: 1, completion: 1, cost: nil, daysAgo: 0),  // same day
            point("m", provider: "p", prompt: 1, completion: 1, cost: nil, daysAgo: 3)
        ]
        #expect(UsageStatisticsAggregator.activeDays(points) == 2)
    }

    @Test func aggregateByProviderGroupsCorrectly() {
        let points = [
            point("gpt-4o", provider: "openai", prompt: 100, completion: 50, cost: 0.01),
            point("claude", provider: "anthropic", prompt: 200, completion: 100, cost: 0.02),
            point("gpt-4.1", provider: "openai", prompt: 50, completion: 25, cost: 0.005)
        ]
        let aggs = UsageStatisticsAggregator.aggregateByProvider(points)
        #expect(aggs.count == 2)
        let openai = aggs.first { $0.key == "openai" }
        #expect(openai?.messageCount == 2)
    }

    @Test func totalsAcrossPoints() {
        let points = [
            point("m", provider: "p", prompt: 100, completion: 50, cost: 0.01),
            point("m", provider: "p", prompt: 200, completion: 100, cost: nil)
        ]
        let t = UsageStatisticsAggregator.totals(points)
        #expect(t.tokens == 450)
        #expect(t.cost == 0.01)   // only the point with a cost contributes
    }

    @Test func emptyPointsProduceEmptyAggregates() {
        #expect(UsageStatisticsAggregator.aggregateByModel([]).isEmpty)
        #expect(UsageStatisticsAggregator.favoriteModel([]) == nil)
        #expect(UsageStatisticsAggregator.activeDays([]) == 0)
        #expect(UsageStatisticsAggregator.totals([]).cost == nil)
    }
}
