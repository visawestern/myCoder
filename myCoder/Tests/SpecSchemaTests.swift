import XCTest
import SQLite
@testable import myCoder

final class SpecSchemaTests: XCTestCase {
    private var projectRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-spec-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            ProjectDatabaseManager.evictProject(projectPath: projectRoot.path)
            try? FileManager.default.removeItem(at: projectRoot)
        }
        projectRoot = nil
        try super.tearDownWithError()
    }

    func testProjectDatabaseCreatesSpecTables() throws {
        let manager = try ProjectDatabaseManager.manager(forProjectPath: projectRoot.path)
        defer { ProjectDatabaseManager.evictProject(projectPath: projectRoot.path) }

        let tables = try tableNames(in: manager.databaseFileURL)
        for table in Self.expectedTables {
            XCTAssertTrue(tables.contains(table), "missing spec table: \(table)")
        }
    }

    func testReopeningProjectDatabaseKeepsSpecSchemaIdempotent() throws {
        _ = try ProjectDatabaseManager.manager(forProjectPath: projectRoot.path)
        ProjectDatabaseManager.evictProject(projectPath: projectRoot.path)

        let reopened = try ProjectDatabaseManager.manager(forProjectPath: projectRoot.path)
        let tables = try tableNames(in: reopened.databaseFileURL)
        for table in Self.expectedTables {
            XCTAssertTrue(tables.contains(table), "missing spec table after reopen: \(table)")
        }
    }

    func testSpecTablesHaveProjectScopeIndexes() throws {
        let manager = try ProjectDatabaseManager.manager(forProjectPath: projectRoot.path)
        defer { ProjectDatabaseManager.evictProject(projectPath: projectRoot.path) }

        let indexes = try indexNames(in: manager.databaseFileURL)
        for index in [
            "idx_spec_checklist_project_order",
            "idx_spec_turns_project_sequence",
            "idx_spec_tz_project_version",
            "idx_spec_requirements_revision",
            "idx_spec_nodes_revision_order",
            "idx_spec_edges_project",
            "idx_spec_history_project_created",
            "idx_spec_node_sessions_node"
        ] {
            XCTAssertTrue(indexes.contains(index), "missing spec index: \(index)")
        }
    }

    private func tableNames(in databaseURL: URL) throws -> Set<String> {
        let connection = try Connection(databaseURL.path)
        let rows = try SQLiteSafeQuery.rows(
            connection.prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
        )
        return Set(rows.compactMap { $0[0] as? String })
    }

    private func indexNames(in databaseURL: URL) throws -> Set<String> {
        let connection = try Connection(databaseURL.path)
        let rows = try SQLiteSafeQuery.rows(
            connection.prepare("SELECT name FROM sqlite_master WHERE type = 'index'")
        )
        return Set(rows.compactMap { $0[0] as? String })
    }

    private static let expectedTables = [
        "project_spec_settings",
        "spec_checklist_items",
        "spec_wizard_turns",
        "spec_tz_revisions",
        "spec_requirements",
        "spec_nodes",
        "spec_edges",
        "spec_history",
        "spec_node_sessions"
    ]
}
