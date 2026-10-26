import Foundation

enum UsageScreenSummaryLogic {
    /// Counts usage-bearing assistant records in the already-filtered period.
    /// This deliberately does not use raw all-time database message counts,
    /// because the Usage screen's other cards are scoped to the selected range.
    static func messageCount(for points: [UsageDataPoint]) -> Int {
        points.count
    }
}
