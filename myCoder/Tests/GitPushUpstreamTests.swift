import Testing
import Foundation
@testable import myCoder

@Suite("Git Push Upstream")
struct GitPushUpstreamTests {

    @Test("Push arguments use plain push when upstream exists")
    func plainPushWithUpstream() {
        #expect(GitRepository.pushArguments(hasUpstream: true, branch: "main") == ["push"])
    }

    @Test("Push arguments set upstream on first push of a new branch")
    func setUpstreamWithoutUpstream() {
        #expect(
            GitRepository.pushArguments(hasUpstream: false, branch: "feature/x")
                == ["push", "--set-upstream", "origin", "feature/x"]
        )
    }

    @Test("hasUpstream is false for a fresh branch without remote tracking")
    func freshBranchHasNoUpstream() throws {
        let repo = try makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        #expect(GitRepository.hasUpstream(in: repo) == false)
    }

    @Test("Push to a bare local remote sets upstream automatically")
    func pushSetsUpstreamAgainstLocalBareRemote() throws {
        let repo = try makeTempRepo()
        let bare = NSTemporaryDirectory() + "mimo-bare-" + UUID().uuidString
        defer {
            try? FileManager.default.removeItem(atPath: repo)
            try? FileManager.default.removeItem(atPath: bare)
        }
        try FileManager.default.createDirectory(atPath: bare, withIntermediateDirectories: true)
        _ = try GitRepository.run(["init", "--bare"], in: bare)
        _ = try GitRepository.run(["remote", "add", "origin", bare], in: repo)

        try "hello".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)
        _ = try GitRepository.commitAll(in: repo, message: "initial")

        let result = try GitRepository.push(in: repo)
        #expect(result.success)
        #expect(GitRepository.hasUpstream(in: repo) == true)
    }

    private func makeTempRepo() throws -> String {
        let dir = NSTemporaryDirectory() + "mimo-upstream-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        _ = try GitRepository.run(["init"], in: dir)
        _ = try GitRepository.run(["config", "user.email", "test@example.com"], in: dir)
        _ = try GitRepository.run(["config", "user.name", "Test"], in: dir)
        return dir
    }
}
