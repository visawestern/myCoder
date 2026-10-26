import Foundation

final class WebChatCompletionSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false

    func recordIfCompleted(_ event: WebChatEvent) {
        guard WebSendCompletionLogic.recordsCompletion(for: event) else { return }
        lock.lock()
        didComplete = true
        lock.unlock()
    }

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let value = didComplete
        didComplete = false
        return value
    }
}
