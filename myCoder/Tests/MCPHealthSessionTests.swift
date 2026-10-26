import Testing
import Foundation
@testable import myCoder

@Suite("MCPHealthSession — concurrency limiter + session cache", .serialized)
struct MCPHealthSessionTests {

    @MainActor
    @Test func sessionCachesResults() {
        let s = MCPHealthSession.shared
        let id = "cache-\(UUID().uuidString.prefix(6))"
        s.update(id, .healthy)
        #expect(s.cachedStatus(for: id) == .healthy)
        #expect(s.cachedStatus(for: id + "-other") == nil)
        s.update(id, .unknown) // cleanup
    }

    @MainActor
    @Test func concurrencyLimitEnforced() {
        let s = MCPHealthSession.shared
        let prefix = "conc-\(UUID().uuidString.prefix(6))"
        var begun = 0
        for i in 0..<10 {
            if s.beginCheck("\(prefix)-\(i)") { begun += 1 }
        }
        #expect(begun <= 3)
        #expect(begun >= 1)
        // cleanup all we started
        for i in 0..<begun { s.update("\(prefix)-\(i)", .healthy) }
    }

    @MainActor
    @Test func beginCheckDeduplicatesInFlight() {
        let s = MCPHealthSession.shared
        let id = "dup-\(UUID().uuidString.prefix(6))"
        #expect(s.beginCheck(id) == true)
        #expect(s.beginCheck(id) == false) // already in-flight
        s.update(id, .unknown) // cleanup
    }

    @MainActor
    @Test func updateReleasesSlot() {
        let s = MCPHealthSession.shared
        let id = "rel-\(UUID().uuidString.prefix(6))"
        #expect(s.beginCheck(id) == true)
        s.update(id, .healthy)
        #expect(s.cachedStatus(for: id) == .healthy)
        // A new check should succeed (slot freed)
        #expect(s.beginCheck(id + "-next") == true)
        s.update(id + "-next", .unknown) // cleanup
    }
}
