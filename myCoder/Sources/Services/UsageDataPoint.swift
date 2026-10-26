import Foundation

/// Harness profile that produced a usage point (eval harness-tax C1/C2).
/// `unknown` = captured before profiles existed (legacy rows stay comparable).
enum HarnessProfile: String, Codable, Equatable, CaseIterable {
    case minimal
    case standard
    case full
    case unknown
}

/// One usage data point read from a database (plan Раздел 10 Блок 2 п.13-14).
/// Cost is nil when the provider supplies no trustworthy price.
struct UsageDataPoint: Equatable {
    let timestamp: Date
    let model: String
    let provider: String
    let promptTokens: Int
    let completionTokens: Int
    let costUSD: Double?
    /// Harness-tax C1: which profile produced this point.
    let profile: HarnessProfile
    /// Harness-tax C1: outgoing initial-context size in bytes (system +
    /// history + new user text, UTF-8). Text only — multimodal parts excluded.
    let contextBytes: Int

    init(timestamp: Date, model: String, provider: String,
         promptTokens: Int, completionTokens: Int, costUSD: Double?,
         profile: HarnessProfile = .unknown, contextBytes: Int = 0) {
        self.timestamp = timestamp
        self.model = model
        self.provider = provider
        self.promptTokens = max(0, promptTokens)
        self.completionTokens = max(0, completionTokens)
        self.costUSD = UsageCostSafety.sanitized(costUSD)
        self.profile = profile
        self.contextBytes = max(0, contextBytes)
    }

    var totalTokens: Int { promptTokens + completionTokens }
}
