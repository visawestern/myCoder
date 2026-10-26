import Foundation

final class WebChatApprovalSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var message: String?

    func record(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        if message == nil { message = value }
    }

    func take() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let value = message
        message = nil
        return value
    }
}
