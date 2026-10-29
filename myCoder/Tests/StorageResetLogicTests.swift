import Testing
import Foundation
@testable import myCoder

@Suite("Storage reset logic (plan Раздел 8)")
struct StorageResetLogicTests {

    private let home = URL(fileURLWithPath: "/home/user")

    @Test func appCacheOnlyClearsTheAppDatabase() {
        let plan = StorageResetLogic.plan(for: .appCacheOnly, homeDirectory: home)
        #expect(plan.deletesPaths == ["/home/user/.mycoder/mycoder.db"])
        #expect(plan.scope == .appCacheOnly)
    }

    @Test func summaryMentionsDeletedPaths() {
        let plan = StorageResetLogic.plan(for: .appCacheOnly, homeDirectory: home)
        let s = StorageResetLogic.summary(for: plan)
        #expect(s.contains("mycoder.db"))
    }

    @Test func fullDatabasePlanCoversGlobalRegistryAndProjectDatabases() {
        let plan = StorageResetLogic.plan(
            for: .fullDatabase,
            homeDirectory: home,
            projectPaths: ["/work/alpha", "/work/beta"]
        )
        #expect(plan.scope == .fullDatabase)
        #expect(plan.deletesPaths.contains("/home/user/.mycoder/mycoder.db"))
        #expect(plan.deletesPaths.contains("/home/user/.mycoder/projects.json"))
        #expect(plan.deletesPaths.contains("/work/alpha/.mycoder/project.db"))
        #expect(plan.deletesPaths.contains("/work/beta/.mycoder/project.db"))
        #expect(plan.deletesPaths.contains("/home/user/.mycoder/projects"))
        #expect(plan.deletesPaths.count == Set(plan.deletesPaths).count)
    }

    @Test func fullDatabasePlanWorksWithoutKnownProjects() {
        let plan = StorageResetLogic.plan(for: .fullDatabase, homeDirectory: home)
        #expect(plan.deletesPaths.contains("/home/user/.mycoder/mycoder.db"))
        #expect(plan.deletesPaths.contains("/home/user/.mycoder/projects.json"))
        #expect(plan.deletesPaths.contains("/home/user/.mycoder/projects"))
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
