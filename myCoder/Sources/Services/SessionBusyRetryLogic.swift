import Foundation

enum SessionBusyRetryLogic {
    static let maxRetries = 3

    struct RetryPlan: Equatable {
        let retryCount: Int
        let sessionID: String
        let assistantMessageID: String
        let messageID: String
    }

    static func shouldRetry(retryCount: Int) -> Bool {
        retryCount >= 0 && retryCount < maxRetries
    }

    static func nextPlan(from current: RetryPlan, isCancelled: Bool = false) -> RetryPlan? {
        guard !isCancelled, shouldRetry(retryCount: current.retryCount) else { return nil }
        return RetryPlan(
            retryCount: current.retryCount + 1,
            sessionID: current.sessionID,
            assistantMessageID: current.assistantMessageID,
            messageID: current.messageID
        )
    }
}
