import Testing
import Foundation
@testable import myCoder

@Suite("Storage reset logic (plan Раздел 8)")
struct StorageResetLogicTests {

    private let home = URL(fileURLWithPath: "/home/user")

    @Test func appCacheOnlyClearsMimoDBOnly() {
        let plan = StorageResetLogic.plan(for: .appCacheOnly, homeDirectory: home)
        #expect(plan.deletesPaths == ["/home/user/.mycoder/mimo.db"])
        #expect(plan.scope == .appCacheOnly)
    }

    @Test func summaryMentionsDeletedPaths() {
        let plan = StorageResetLogic.plan(for: .appCacheOnly, homeDirectory: home)
        let s = StorageResetLogic.summary(for: plan)
        #expect(s.contains("mimo.db"))
    }

    // MARK: - Identifier normalization (Блок 2 п.17)

    @Test func projectIDStripsTrailingSlash() {
        #expect(IdentifierNormalization.projectID(for: "/foo/bar/") == "/foo/bar")
        #expect(IdentifierNormalization.projectID(for: "/foo/bar") == "/foo/bar")
    }

    @Test func sameProjectMatchesPathsWithTrailingSlash() {
        #expect(IdentifierNormalization.sameProject("/foo/bar", "/foo/bar/"))
    }

    @Test func differentPathsAreDifferentProjects() {
        #expect(!IdentifierNormalization.sameProject("/foo/bar", "/foo/baz"))
    }
}
