import Testing
import Foundation
@testable import myCoder

@Suite("GitRepository remotes")
struct GitRepositoryRemoteTests {

    private func makeTempRepo() throws -> String {
        let dir = NSTemporaryDirectory() + "mimo-remote-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        _ = try GitRepository.run(["init"], in: dir)
        return dir
    }

    @Test("Fresh repository has no remotes")
    func freshRepoHasNoRemotes() throws {
        let repo = try makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        #expect(try GitRepository.remotes(in: repo).isEmpty)
    }

    @Test("Repository with origin lists it")
    func repoWithOriginListsIt() throws {
        let repo = try makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        _ = try GitRepository.run(["remote", "add", "origin", "https://example.com/demo.git"], in: repo)
        #expect(try GitRepository.remotes(in: repo) == ["origin"])
    }
}
