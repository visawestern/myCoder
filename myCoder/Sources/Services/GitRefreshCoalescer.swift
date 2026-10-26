import Foundation

actor GitRefreshCoalescer {
    private var inFlight: [String: Any] = [:]

    func run<T: Sendable>(key: String, operation: @escaping @Sendable () async -> T) async -> T {
        if let existing = inFlight[key] as? Task<T, Never> {
            return await existing.value
        }

        let task = Task { await operation() }
        inFlight[key] = task
        let value = await task.value
        inFlight[key] = nil
        return value
    }
}
