import Foundation

/// Bridges synchronous WebChatDriver events to the MainActor turn coordinator.
/// Exactly one reason is retained; later duplicate injection errors are ignored.
final class WebChatRetrySignal: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: String?

    func record(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        if reason == nil { reason = value }
    }

    func take() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let value = reason
        reason = nil
        return value
    }
}
