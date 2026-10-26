import Testing
import Foundation
@testable import myCoder

@Suite("RepoRoot — robust repo-relative paths (audit B6)")
struct RepoRootTests {

    @Test func rootContainsPackageManifest() {
        let manifest = RepoRoot.url.appendingPathComponent("Package.swift")
        #expect(FileManager.default.fileExists(atPath: manifest.path),
                "RepoRoot.url should point at a directory containing Package.swift")
    }

    @Test func sourceTextThrowsForMissingFile() {
        #expect(throws: (any Error).self) {
            _ = try RepoRoot.sourceText("definitely/not/a/real/file.swift")
        }
    }

    @Test func urlIsStableAcrossCalls() {
        #expect(RepoRoot.url == RepoRoot.url)
    }
}
