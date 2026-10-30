import Testing
import Foundation
@testable import myCoder

/// Агрегация статистики использования: санитизация стоимости, нормализация
/// имён моделей, агрегаты по модели/провайдеру/профилю, фаворит,
/// активные дни, итоги и строковый формат стоимости.
@Suite("Агрегация статистики использования (UsageStatisticsAggregator)")
struct UsageStatisticsAggregatorTests {

    private func point(model: String = "gpt-4o",
                       provider: String = "openai",
                       prompt: Int = 10,
                       completion: Int = 5,
                       cost: Double? = 0.01,
                       date: Date = Date(timeIntervalSince1970: 1_700_000_000),
                       profile: HarnessProfile = .standard) -> UsageDataPoint {
        UsageDataPoint(
            timestamp: date,
            model: model,
            provider: provider,
            promptTokens: prompt,
            completionTokens: completion,
            costUSD: cost,
            profile: profile
        )
    }

    @Test("Стоимость: отрицательные/NaN/бесконечные значения → N/A")
    func costSafetySanitizes() {
        #expect(UsageCostSafety.sanitized(0.5) == 0.5)
        #expect(UsageCostSafety.sanitized(0) == 0)
        #expect(UsageCostSafety.sanitized(-1) == nil)
        #expect(UsageCostSafety.sanitized(.nan) == nil)
        #expect(UsageCostSafety.sanitized(.infinity) == nil)
        #expect(UsageCostSafety.sanitized(nil) == nil)
    }

    @Test("UsageCapture санитизирует токены и id")
    func captureSanitizes() {
        let capture = UsageCapture(promptTokens: -5, completionTokens: 3, costUSD: -1,
                                   modelID: "", providerID: "")
        #expect(capture.promptTokens == 0)
        #expect(capture.completionTokens == 3)
        #expect(capture.costUSD == nil, "отрицательная стоимость → nil (N/A)")
        #expect(capture.modelID == "unknown")
        #expect(capture.providerID == "unknown")
        #expect(capture.totalTokens == 3)
        #expect(!capture.hasCost)
        #expect(UsageCapture(promptTokens: 0, completionTokens: 0, costUSD: nil,
                             modelID: "m", providerID: "p").isZero)
    }

    @Test("Нормализация имени модели обрезает дату/снапшот-суффикс")
    func modelNameNormalization() {
        #expect(UsageStatisticsAggregator.normalizeModelName("gpt-4o-2024-08-06") == "gpt-4o")
        #expect(UsageStatisticsAggregator.normalizeModelName("gpt-4o-20240806") == "gpt-4o")
        #expect(UsageStatisticsAggregator.normalizeModelName("claude-3-5-sonnet") == "claude-3-5-sonnet")
        #expect(UsageStatisticsAggregator.normalizeModelName("gpt-4o") == "gpt-4o")
    }

    @Test("Агрегация по модели объединяет даты-варианты и сортирует по токенам")
    func aggregateByModelCombinesDates() {
        let points = [
            point(model: "gpt-4o-2024-08-06", prompt: 100, completion: 100, cost: 1),
            point(model: "gpt-4o", prompt: 50, completion: 50, cost: 0.5),
            point(model: "claude", prompt: 10, completion: 10, cost: 0.1)
        ]
        let aggregates = UsageStatisticsAggregator.aggregateByModel(points)
        #expect(aggregates.first?.key == "gpt-4o")
        #expect(aggregates.first?.messageCount == 2)
        #expect(aggregates.first?.promptTokens == 150)
        #expect(aggregates.first?.completionTokens == 150)
        #expect(aggregates.first?.totalTokens == 300)
        #expect(aggregates.first?.costUSD == 1.5)
        #expect(aggregates[1].key == "claude")
    }

    @Test("Агрегация по провайдеру и профилю")
    func aggregateByProviderAndProfile() {
        let points = [
            point(provider: "openai", cost: 1),
            point(provider: "openai", cost: 2),
            point(provider: "ollama", cost: nil)
        ]
        let byProvider = UsageStatisticsAggregator.aggregateByProvider(points)
        #expect(byProvider.first?.key == "openai")
        #expect(byProvider.first?.costUSD == 3)
        #expect(byProvider.last?.key == "ollama")
        #expect(byProvider.last?.costUSD == nil, "локальный провайдер без стоимости")

        let byProfile = UsageStatisticsAggregator.aggregateByProfile(points)
        #expect(!byProfile.isEmpty)
        #expect(byProfile.allSatisfy { $0.messageCount >= 1 })
    }

    @Test("Фаворит — по объёму токенов, не по выбору")
    func favoriteModelUsesTokenVolume() {
        let points = [
            point(model: "gpt-4o", prompt: 10, completion: 10),
            point(model: "claude", prompt: 500, completion: 500)
        ]
        #expect(UsageStatisticsAggregator.favoriteModel(points) == "claude")
    }

    @Test("Активные дни считаются уникальными календарными днями")
    func activeDaysCountsUniqueDays() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(86400)
        let sameDay = day1.addingTimeInterval(3600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let points = [point(date: day1), point(date: sameDay), point(date: day2)]
        #expect(UsageStatisticsAggregator.activeDays(points, calendar: calendar) == 2)
    }

    @Test("Итоги: сумма токенов и общая стоимость (если есть)")
    func totalsSum() {
        let points = [
            point(prompt: 100, completion: 50, cost: 1),
            point(prompt: 10, completion: 10, cost: 0.5)
        ]
        let totals = UsageStatisticsAggregator.totals(points)
        #expect(totals.tokens == 170)
        #expect(totals.cost == 1.5)
        #expect(UsageStatisticsAggregator.totals([point(cost: nil)]).cost == nil)
    }

    @Test("costLabel: N/A для локальных, $X.XX для денег")
    func costLabelFormat() {
        #expect(UsageStatisticsAggregator.costLabel(nil) == "N/A")
        #expect(UsageStatisticsAggregator.costLabel(2.5) == "$2.50")
        #expect(UsageStatisticsAggregator.costLabel(-1) == "N/A")
    }

    @Test("Фильтр по диапазону дат")
    func dateRangeFilter() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let range = UsageDateRange.lastDays(7, now: now)
        #expect(range.contains(now.addingTimeInterval(-86400)))
        #expect(!range.contains(now.addingTimeInterval(-8 * 86400)))
        let points = [
            point(date: now.addingTimeInterval(-86400)),
            point(date: now.addingTimeInterval(-30 * 86400))
        ]
        #expect(UsageStatisticsAggregator.filter(points, range: range).count == 1)
        #expect(UsageStatisticsAggregator.filter(points, range: nil).count == 2)
    }
}
