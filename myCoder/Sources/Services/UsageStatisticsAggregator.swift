import Foundation

/// Cost values are provider-reported data, not estimates. A missing, negative,
/// NaN, or infinite value cannot be presented as a monetary charge.
enum UsageCostSafety {
    static func sanitized(_ costUSD: Double?) -> Double? {
        guard let costUSD, costUSD.isFinite, costUSD >= 0 else { return nil }
        return costUSD
    }
}

/// Runtime usage captured from a provider response before persistence.
/// `costUSD` is nil for local providers (Ollama/mimoCLI) where no price applies.
struct UsageCapture: Equatable {
    let promptTokens: Int
    let completionTokens: Int
    let costUSD: Double?
    let modelID: String
    let providerID: String
    /// Harness-tax C1: profile that produced this capture (C2 fills real values).
    let profile: HarnessProfile
    /// Harness-tax C1: outgoing initial-context bytes (text only).
    let contextBytes: Int

    var totalTokens: Int { promptTokens + completionTokens }

    init(promptTokens: Int, completionTokens: Int, costUSD: Double?, modelID: String, providerID: String,
         profile: HarnessProfile = .unknown, contextBytes: Int = 0) {
        self.promptTokens = max(0, promptTokens)
        self.completionTokens = max(0, completionTokens)
        self.costUSD = UsageCostSafety.sanitized(costUSD)
        self.modelID = modelID.isEmpty ? "unknown" : modelID
        self.providerID = providerID.isEmpty ? "unknown" : providerID
        self.profile = profile
        self.contextBytes = max(0, contextBytes)
    }

    /// True when a cost figure is available (including zero cost). Distinct from
    /// `nil`, which means cost is N/A (local provider).
    var hasCost: Bool { costUSD != nil }

    /// True when no tokens were recorded — such captures should not become
    /// data points (avoids zero rows polluting aggregates).
    var isZero: Bool { promptTokens == 0 && completionTokens == 0 }

    /// Build a capture from an ACP response's `usage`. ACP carries no cost, so
    /// `costUSD` is always nil here (N/A).
    init(acpUsage: ACPUsage, modelID: String, providerID: String) {
        self.init(
            promptTokens: acpUsage.promptTokens ?? 0,
            completionTokens: acpUsage.completionTokens ?? 0,
            costUSD: nil,
            modelID: modelID,
            providerID: providerID
        )
    }
}

/// Per-model (or per-provider) aggregate (plan Блок 2 п.16/п.38).
struct UsageAggregate: Equatable {
    let key: String              // model id or provider id
    var messageCount: Int
    var promptTokens: Int
    var completionTokens: Int
    var costUSD: Double?         // nil when no data point had a cost (local-only)

    var totalTokens: Int { promptTokens + completionTokens }
}

/// A time window filter (plan Блок 2 п.15).
struct UsageDateRange: Equatable {
    let start: Date
    let end: Date

    static func lastDays(_ days: Int, now: Date = Date()) -> UsageDateRange {
        UsageDateRange(start: now.addingTimeInterval(-Double(days) * 86400), end: now)
    }

    func contains(_ date: Date) -> Bool { date >= start && date <= end }
}

/// Pure aggregation of usage statistics from real DB rows (plan Раздел 10 Блок 2).
/// No hardcoded "—" or "$0.00" — cost is nil (N/A) when inapplicable.
enum UsageStatisticsAggregator {

    /// Filter points to a date range (plan Блок 2 п.15).
    static func filter(_ points: [UsageDataPoint], range: UsageDateRange?) -> [UsageDataPoint] {
        guard let range = range else { return points }
        return points.filter { range.contains($0.timestamp) }
    }

    /// Normalize a model id so `gpt-4o-2024-08-06` and `gpt-4o` aggregate together
    /// (plan Блок 4 п.49). Strips a trailing date/snapshot suffix.
    static func normalizeModelName(_ model: String) -> String {
        // Remove a trailing "-YYYY-MM-DD" or "-YYYYMMDD" snapshot suffix.
        let patterns = ["-\\d{4}-\\d{2}-\\d{2}$", "-\\d{8}$"]
        var result = model
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        return result
    }

    /// Aggregate by model (normalized) (plan Блок 2 п.16).
    static func aggregateByModel(_ points: [UsageDataPoint], normalize: Bool = true) -> [UsageAggregate] {
        aggregate(points) { normalize ? normalizeModelName($0.model) : $0.model }
    }

    /// Aggregate by provider (plan Блок 4 п.38).
    static func aggregateByProvider(_ points: [UsageDataPoint]) -> [UsageAggregate] {
        aggregate(points) { $0.provider }
    }

    /// Aggregate by harness profile (eval harness-tax C1): messageCount per
    /// profile is the turn proxy, tokens/cost show the profile's price.
    static func aggregateByProfile(_ points: [UsageDataPoint]) -> [UsageAggregate] {
        aggregate(points) { $0.profile.rawValue }
    }

    private static func aggregate(_ points: [UsageDataPoint], key: (UsageDataPoint) -> String) -> [UsageAggregate] {
        var map: [String: UsageAggregate] = [:]
        for p in points {
            let k = key(p)
            var agg = map[k] ?? UsageAggregate(key: k, messageCount: 0, promptTokens: 0, completionTokens: 0, costUSD: nil)
            agg.messageCount += 1
            agg.promptTokens += p.promptTokens
            agg.completionTokens += p.completionTokens
            if let cost = p.costUSD {
                agg.costUSD = (agg.costUSD ?? 0) + cost
            }
            map[k] = agg
        }
        // Sort by total tokens desc for a stable, meaningful order.
        return map.values.sorted { $0.totalTokens > $1.totalTokens }
    }

    /// The most-used model by token volume over the period (plan Блок 2 п.19).
    /// This is BY ACTUAL USAGE, not the currently-selected model.
    static func favoriteModel(_ points: [UsageDataPoint]) -> String? {
        aggregateByModel(points).first?.key
    }

    /// Number of unique calendar days with at least one message (plan Блок 2 п.20).
    /// Correctly counts distinct days, not reused session count.
    static func activeDays(_ points: [UsageDataPoint], calendar: Calendar = .current) -> Int {
        let days = Set(points.map { calendar.startOfDay(for: $0.timestamp) })
        return days.count
    }

    /// Total tokens/cost across all points (cost nil if no point had cost).
    static func totals(_ points: [UsageDataPoint]) -> (tokens: Int, cost: Double?) {
        let tokens = points.reduce(0) { $0 + $1.totalTokens }
        let costs = points.compactMap { $0.costUSD }
        return (tokens, costs.isEmpty ? nil : costs.reduce(0, +))
    }

    /// Cost display: "N/A" for local providers, formatted USD otherwise
    /// (plan Блок 2 п.22 — no misleading "$0.00").
    static func costLabel(_ cost: Double?) -> String {
        guard let cost = UsageCostSafety.sanitized(cost) else { return "N/A" }
        return String(format: "$%.2f", cost)
    }
}
