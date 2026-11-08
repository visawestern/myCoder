import Foundation

/// Deadlines on a dedicated thread.
///
/// Neither GCD's global queue nor Swift's cooperative pool can be trusted to
/// run a timer on time. Under load — the full selftest runs thousands of
/// parallel tests, many of them blocking a thread — a timer scheduled there
/// fired SECONDS late (measured: 4.2 s for a 100 ms deadline), and a late
/// deadline is exactly what this timer exists to prevent: the caller waits
/// longer than the budget it was promised.
///
/// One dedicated thread owns every deadline: it waits for the earliest due
/// date and fires the callbacks itself. The timing then depends on nothing
/// but the clock, never on how busy the process is.
final class DeadlineTimer: @unchecked Sendable {

    /// Shared instance: one timer thread for the whole process.
    static let shared = DeadlineTimer()

    private struct Entry {
        /// Absolute fire time (seconds since 1970).
        let due: TimeInterval
        let fire: () -> Void
    }

    private let condition = NSCondition()
    private var entries: [Entry] = []
    private var threadStarted = false

    /// Fires `fire` after `seconds`. The callback runs on the timer thread.
    func schedule(after seconds: TimeInterval, fire: @escaping () -> Void) {
        let due = Date().addingTimeInterval(seconds)
        condition.lock()
        entries.append(Entry(due: due.timeIntervalSince1970, fire: fire))
        if !threadStarted {
            threadStarted = true
            let thread = Thread { [weak self] in self?.loop() }
            thread.name = "com.mycoder.deadline-timer"
            thread.stackSize = 512 * 1024
            thread.start()
        }
        condition.signal()
        condition.unlock()
    }

    /// Wait for the earliest deadline, fire everything that is due, repeat.
    private func loop() {
        while true {
            condition.lock()
            if entries.isEmpty {
                condition.wait()
                condition.unlock()
                continue
            }
            let now = Date().timeIntervalSince1970
            let earliest = entries.map(\.due).min() ?? now
            let remaining = earliest - now
            if remaining > 0 {
                // Timed wait: wakes up when a new deadline arrives sooner.
                condition.wait(until: Date().addingTimeInterval(remaining))
                condition.unlock()
                continue
            }
            var due: [Entry] = []
            entries.removeAll { entry in
                if entry.due <= now {
                    due.append(entry)
                    return true
                }
                return false
            }
            condition.unlock()
            for entry in due {
                entry.fire()
            }
        }
    }
}
