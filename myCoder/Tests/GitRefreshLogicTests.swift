import Testing
import Foundation
@testable import myCoder

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

    @Test("Coalescer reuses in-flight refresh")
    func coalescerReusesInFlight() async {
        let coalescer = GitRefreshCoalescer()
        let counter = Counter()

        async let first: Int = coalescer.run(key: "main") {
            let n = counter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return n
        }
        async let second: Int = coalescer.run(key: "main") {
            return counter.increment()
        }

        let results = await [first, second]
        #expect(results[0] == results[1])
        #expect(counter.count == 1)
    }

    @Test("Resolves session id for git refresh")
    func resolvesSessionID() {
        #expect(GitRefreshScheduler.resolvedSessionID(explicit: "ses_a", selected: "ses_b") == "ses_a")
        #expect(GitRefreshScheduler.resolvedSessionID(explicit: nil, selected: "ses_b") == "ses_b")
        #expect(GitRefreshScheduler.resolvedSessionID(explicit: "", selected: "") == nil)
    }
}
