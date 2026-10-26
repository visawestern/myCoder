import Testing
import Foundation
@testable import myCoder

/// Confirmation gate for destructive project deletion (plan Раздел 8 п.24/п.54:
/// "требование ввода названия проекта для подтверждения деструктивной операции",
/// GitHub "type repo name to delete" pattern).
@Suite("Project deletion confirmation gate (plan Раздел 8 п.24/п.54)")
struct ProjectDeleteConfirmationTests {

    @Test func exactNameConfirms() {
        #expect(ProjectDeleteConfirmation.isConfirmed(projectName: "my-app", typed: "my-app"))
    }

    @Test func emptyOrMismatchRejects() {
        #expect(!ProjectDeleteConfirmation.isConfirmed(projectName: "my-app", typed: ""))
        #expect(!ProjectDeleteConfirmation.isConfirmed(projectName: "my-app", typed: "my-ap"))
        #expect(!ProjectDeleteConfirmation.isConfirmed(projectName: "my-app", typed: "myapp"))
    }

    @Test func caseSensitiveLikeGitHub() {
        #expect(!ProjectDeleteConfirmation.isConfirmed(projectName: "MyApp", typed: "myapp"))
    }

    @Test func trimmingIsAppliedToTypedInputOnly() {
        // Leading/trailing whitespace from the field must not bypass the gate.
        #expect(ProjectDeleteConfirmation.isConfirmed(projectName: "my-app", typed: " my-app "))
    }

    @Test func deletePathScopeIsDataOnly() {
        // The plan's promise: user files on disk are NEVER deleted — only the
        // project's .mycoder data directory.
        let home = URL(fileURLWithPath: "/Users/test")
        let projectPath = URL(fileURLWithPath: "/Users/test/Projects/MyApp")
        let dataDir = ProjectDatabaseLocator.projectMimoDir(projectPath: projectPath.path)
        let relative = dataDir.path.replacingOccurrences(of: home.path, with: "")
        #expect(relative.hasPrefix("/Projects/MyApp/.mycoder"))
        #expect(!dataDir.path.contains("..")) // no path traversal
    }
}
