import Testing
import Foundation
@testable import myCoder

@MainActor
@Suite("Git refresh logic")
struct GitRefreshLogicTests {

    @Test("Remote git only when local git failed")
    func remoteOnlyOnLocalFailure() {
        #expect(SessionContextLoader.shouldFetchRemoteGit(localChangeCount: 0, localGitFailed: false) == false)
        #expect(SessionContextLoader.shouldFetchRemoteGit(localChangeCount: 5, localGitFailed: false) == false)
        #expect(SessionContextLoader.shouldFetchRemoteGit(localChangeCount: 0, localGitFailed: true) == true)
    }

    /// Thread-safe call counter — the two closures run concurrently, so a plain
    /// captured `var` would be a data race under the Swift 6 language mode.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() -> Int {
            lock.lock(); defer { lock.unlock() }
            value += 1
            return value
        }
        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    /// Test double: an async gate that keeps the first refresh running until
    /// the test has proved that the second call joined it. Without this the
    /// old test raced the scheduler — the second call sometimes started only
    /// after the first had already finished, which is a different (valid)
    /// situation and made the suite flaky.
    final class AsyncGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            lock.lock()
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            lock.unlock()
            for waiter in pending { waiter.resume() }
        }

        func wait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if isOpen {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }
    }

    @Test("Coalescer reuses in-flight refresh")
    func coalescerReusesInFlight() async {
        let coalescer = GitRefreshCoalescer()
        let counter = Counter()
        let gate = AsyncGate()

        let first = Task { await coalescer.run(key: "main") { () -> Int in
            let n = counter.increment()
            await gate.wait()
            return n
        } }

        // Wait until the first refresh has really started.
        for _ in 0..<100 where counter.count == 0 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(counter.count == 1)

        let second = Task { await coalescer.run(key: "main") { counter.increment() } }

        // The second call must join the running refresh, not start its own.
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(counter.count == 1)

        gate.open()
        let results = await [first.value, second.value]
        #expect(results[0] == results[1])
        #expect(counter.count == 1)
    }

    @Test("Coalescer starts a fresh refresh after the previous one finished")
    func coalescerStartsFreshAfterCompletion() async {
        let coalescer = GitRefreshCoalescer()
        let counter = Counter()

        let first = await coalescer.run(key: "main") { counter.increment() }
        let second = await coalescer.run(key: "main") { counter.increment() }

        #expect(first == 1)
        #expect(second == 2)
        #expect(counter.count == 2)
    }

    @Test("Resolves session id for git refresh")
    func resolvesSessionID() {
        #expect(GitRefreshScheduler.resolvedSessionID(explicit: "ses_a", selected: "ses_b") == "ses_a")
        #expect(GitRefreshScheduler.resolvedSessionID(explicit: nil, selected: "ses_b") == "ses_b")
        #expect(GitRefreshScheduler.resolvedSessionID(explicit: "", selected: "") == nil)
    }
}
