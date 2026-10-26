import Testing
import Foundation
@testable import myCoder

@Suite("Git repository operations")
struct GitRepositoryTests {

    private func makeTempRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-git-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.path
        _ = try GitRepository.run(["init", "-b", "main"], in: path)
        _ = try GitRepository.run(["config", "user.email", "test@mimo.local"], in: path)
        _ = try GitRepository.run(["config", "user.name", "MiMo Test"], in: path)
        let readme = dir.appendingPathComponent("README.md")
        try "hello".write(to: readme, atomically: true, encoding: .utf8)
        _ = try GitRepository.run(["add", "README.md"], in: path)
        _ = try GitRepository.run(["commit", "-m", "init"], in: path)
        return path
    }

    @Test("Resolves repository root from subdirectory")
    func repositoryRoot() throws {
        let path = try makeTempRepo()
        let sub = URL(fileURLWithPath: path).appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let root = try GitRepository.repositoryRoot(for: sub.path)
        #expect(GitRepository.normalizePath(root) == GitRepository.normalizePath(path))
    }

    @Test("Current branch returns main after init")
    func currentBranch() throws {
        let path = try makeTempRepo()
        let branch = GitRepository.currentBranch(in: path)
        #expect(branch == "main")
    }

    @Test("Working tree diff detects modified file")
    func workingTreeDiff() throws {
        let path = try makeTempRepo()
        let readme = URL(fileURLWithPath: path).appendingPathComponent("README.md")
        try "line1\nline2".write(to: readme, atomically: true, encoding: .utf8)
        let changes = try GitRepository.workingTreeChanges(in: path)
        #expect(changes.count == 1)
        #expect(changes[0].path.hasSuffix("README.md"))
        #expect(changes[0].status == "modified")
        #expect(changes[0].additions + changes[0].deletions > 0)
    }

    @Test("Commit stages and commits all changes")
    func commitAll() throws {
        let path = try makeTempRepo()
        let readme = URL(fileURLWithPath: path).appendingPathComponent("README.md")
        try "updated".write(to: readme, atomically: true, encoding: .utf8)
        let result = try GitRepository.commitAll(in: path, message: "update readme")
        #expect(result.success)
        let changes = try GitRepository.workingTreeChanges(in: path)
        #expect(changes.isEmpty)
    }

    @Test("Commit rejects empty message")
    func commitEmptyMessage() {
        #expect(throws: GitCommandError.emptyCommitMessage) {
            try GitRepository.commitAll(in: "/tmp", message: "   ")
        }
    }

    @Test("Maps local changes to VCS file diff model")
    func mapToVcsDiff() throws {
        let path = try makeTempRepo()
        let readme = URL(fileURLWithPath: path).appendingPathComponent("README.md")
        try "line1\nline2".write(to: readme, atomically: true, encoding: .utf8)
        let local = try GitRepository.workingTreeChanges(in: path)
        let mapped = GitRepository.toVcsFileDiffs(local)
        #expect(mapped.count == 1)
        #expect(mapped[0].status == "modified")
    }

    @Test("Branch list includes main")
    func listBranches() throws {
        let path = try makeTempRepo()
        let branches = try GitRepository.branches(in: path)
        #expect(branches.contains("main"))
    }
}
