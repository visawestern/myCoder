import Testing
import Foundation
@testable import myCoder

@Suite("Project files cache (audit P12 — @ dropdown was empty)")
struct ProjectFilesCacheLogicTests {

    @Test func rescanWhenNoCache() {
        #expect(ProjectFilesCacheLogic.needsRescan(cache: nil, currentPath: "/p"))
    }

    @Test func noRescanForEmptyPath() {
        #expect(!ProjectFilesCacheLogic.needsRescan(cache: nil, currentPath: ""))
    }

    @Test func rescanWhenProjectChanged() {
        let cache = ProjectFilesCacheState(projectPath: "/a", fileNames: ["x"], scannedAt: Date())
        #expect(ProjectFilesCacheLogic.needsRescan(cache: cache, currentPath: "/b"))
    }

    @Test func rescanWhenStale() {
        let old = ProjectFilesCacheState(projectPath: "/p", fileNames: ["x"],
                                         scannedAt: Date(timeIntervalSinceNow: -60))
        #expect(ProjectFilesCacheLogic.needsRescan(cache: old, currentPath: "/p"))
    }

    @Test func noRescanWhenFresh() {
        let fresh = ProjectFilesCacheState(projectPath: "/p", fileNames: ["x"], scannedAt: Date())
        #expect(!ProjectFilesCacheLogic.needsRescan(cache: fresh, currentPath: "/p"))
    }

    @Test func fileNamesForMatchingProject() {
        let cache = ProjectFilesCacheState(projectPath: "/p", fileNames: ["a", "b"], scannedAt: Date())
        #expect(ProjectFilesCacheLogic.fileNames(cache: cache, currentPath: "/p") == ["a", "b"])
        #expect(ProjectFilesCacheLogic.fileNames(cache: cache, currentPath: "/other").isEmpty)
        #expect(ProjectFilesCacheLogic.fileNames(cache: nil, currentPath: "/p").isEmpty)
    }

    // End-to-end with the real scanner: the @ list is actually populated now.
    @Test func realScanPopulatesFileList() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-atlist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let names = ProjectFileScanner.scan(root: root.path).map { $0.path }
        #expect(names.contains("README.md"))
    }
}
