import Testing
@testable import myCoder

@Suite("New Project validation")
struct NewProjectValidationLogicTests {
    @Test("validates trimmed name and existing directory")
    func acceptsValidDirectory() {
        let result = NewProjectValidationLogic.validate(
            name: "  myCoder  ",
            path: "  /tmp/mycoder  ",
            fileExists: { _ in true },
            isDirectory: { _ in true }
        )
        #expect(result == .valid(name: "myCoder", path: "/tmp/mycoder"))
    }

    @Test("rejects a missing project directory before database creation")
    func rejectsMissingDirectory() {
        let result = NewProjectValidationLogic.validate(
            name: "Project",
            path: "/does/not/exist",
            fileExists: { _ in false },
            isDirectory: { _ in false }
        )
        #expect(result == .invalid(.directoryNotFound))
    }

    @Test("rejects a file path as a project root")
    func rejectsFilePath() {
        let result = NewProjectValidationLogic.validate(
            name: "Project",
            path: "/tmp/file.txt",
            fileExists: { _ in true },
            isDirectory: { _ in false }
        )
        #expect(result == .invalid(.notDirectory))
    }

    @Test("rejects blank fields after trimming")
    func rejectsBlankFields() {
        #expect(NewProjectValidationLogic.validate(name: "  ", path: "/tmp", fileExists: { _ in true }, isDirectory: { _ in true }) == .invalid(.emptyName))
        #expect(NewProjectValidationLogic.validate(name: "Project", path: "  ", fileExists: { _ in true }, isDirectory: { _ in true }) == .invalid(.emptyPath))
    }
}
