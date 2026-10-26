import Foundation

enum MessageHistoryPaginationLogic {
    static let initialLimit = 20

    static func nextLimit(after currentLimit: Int) -> Int {
        max(initialLimit, currentLimit) + initialLimit
    }

    static func hasMore(receivedCount: Int, requestedLimit: Int) -> Bool {
        receivedCount >= requestedLimit
    }
}
