import Testing
import Foundation
@testable import myCoder

/// E30 (Раздел 8 — полноценное администрирование проектов): the sidebar loads
/// projects through `DatabaseManager.getAllProjects()`, which silently applied
/// `LIMIT 100` by default. A user with more than 100 projects loses the rest
/// from the UI with no indication. The cap must be explicit, not hidden.
@Suite("E30 — no silent 100-project cap on the projects list")
struct E30ProjectsCapTests {

    @Test("getAllProjects returns every project, not just the first 100")
    func noHidden100Cap() throws {
        let db = DatabaseManager(inMemory: true)
        for i in 0..<150 {
            try db.insertProject(id: "p\(i)", name: "Project \(i)", path: "/tmp/projects/p\(i)")
        }
        let all = try db.getAllProjects()
        #expect(all.count == 150,
                "getAllProjects silently truncated to \(all.count)/150 — sidebar hides projects")
    }

    @Test("an explicit limit is still honored by callers that want one")
    func explicitLimitStillWorks() throws {
        let db = DatabaseManager(inMemory: true)
        for i in 0..<30 {
            try db.insertProject(id: "p\(i)", name: "Project \(i)", path: "/tmp/projects/p\(i)")
        }
        let capped = try db.getAllProjects(limit: 10)
        #expect(capped.count == 10)
    }
}
