import Foundation

enum UsageDataSourcesLogic {
    static func merge(
        legacy: [UsageDataPoint],
        projects: [[UsageDataPoint]]
    ) -> [UsageDataPoint] {
        (legacy + projects.flatMap { $0 }).sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.provider != $1.provider { return $0.provider < $1.provider }
            return $0.model < $1.model
        }
    }
}
