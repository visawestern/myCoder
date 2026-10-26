import Foundation
import Testing
@testable import myCoder

@Suite("Usage data sources")
struct UsageDataSourcesLogicTests {
    private func point(_ model: String, cost: Double?) -> UsageDataPoint {
        UsageDataPoint(
            timestamp: Date(timeIntervalSince1970: 1),
            model: model,
            provider: "provider",
            promptTokens: 10,
            completionTokens: 5,
            costUSD: cost
        )
    }

    @Test("project-scoped points are included with legacy points")
    func mergesAllStores() {
        let merged = UsageDataSourcesLogic.merge(
            legacy: [point("legacy-model", cost: 0.01)],
            projects: [[point("project-model", cost: 0.02)]]
        )
        #expect(merged.map(\.model) == ["legacy-model", "project-model"])
        #expect(merged.compactMap(\.costUSD) == [0.01, 0.02])
    }

    @Test("empty stores produce an empty usage series")
    func emptySources() {
        #expect(UsageDataSourcesLogic.merge(legacy: [], projects: []).isEmpty)
    }
}
