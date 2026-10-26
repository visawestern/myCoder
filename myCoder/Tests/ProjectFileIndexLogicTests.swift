import Testing
import Foundation
@testable import myCoder

@Suite("Project file index logic (plan Раздел 7)")
struct ProjectFileIndexLogicTests {

    // MARK: - Locator

    @Test func databaseAndSnapshotPathsArePerProject() {
        let db = ProjectDatabaseLocator.databaseURL(projectPath: "/home/u/proj")
        #expect(db.path == "/home/u/proj/.mycoder/project.db")
        let snaps = ProjectDatabaseLocator.snapshotsDir(projectPath: "/home/u/proj")
        #expect(snaps.path == "/home/u/proj/.mycoder/snapshots")
    }

    @Test func stableProjectIDNormalizesPath() {
        #expect(ProjectDatabaseLocator.stableProjectID(projectPath: "/home/u/proj/") ==
                ProjectDatabaseLocator.stableProjectID(projectPath: "/home/u/proj"))
    }

    // MARK: - Excludes

    @Test func excludesGitAndNodeModules() {
        #expect(ProjectFileIndexLogic.shouldExclude(relativePath: ".git/config"))
        #expect(ProjectFileIndexLogic.shouldExclude(relativePath: "node_modules/x/index.js"))
        #expect(ProjectFileIndexLogic.shouldExclude(relativePath: ".mycoder/project.db"))
        #expect(!ProjectFileIndexLogic.shouldExclude(relativePath: "src/main.swift"))
    }

    @Test func gitignoreExtPattern() {
        #expect(ProjectFileIndexLogic.matchesGitignore(relativePath: "a/b.log", pattern: "*.log"))
        #expect(!ProjectFileIndexLogic.matchesGitignore(relativePath: "a/b.swift", pattern: "*.log"))
    }

    @Test func gitignoreDirPattern() {
        #expect(ProjectFileIndexLogic.matchesGitignore(relativePath: "build/out.o", pattern: "build/"))
        #expect(ProjectFileIndexLogic.matchesGitignore(relativePath: "src/gen/x", pattern: "gen"))
    }

    @Test func gitignoreCommentAndEmptyIgnored() {
        #expect(!ProjectFileIndexLogic.matchesGitignore(relativePath: "a", pattern: "# comment"))
        #expect(!ProjectFileIndexLogic.matchesGitignore(relativePath: "a", pattern: ""))
    }

    @Test func shouldIndexRespectsSizeAndExcludes() {
        #expect(ProjectFileIndexLogic.shouldIndex(relativePath: "src/a.swift", size: 1000))
        #expect(!ProjectFileIndexLogic.shouldIndex(relativePath: "src/a.swift", size: 10_000_000))  // too big
        #expect(!ProjectFileIndexLogic.shouldIndex(relativePath: ".git/x", size: 10))
        #expect(!ProjectFileIndexLogic.shouldIndex(relativePath: "logs/x.log", size: 10, gitignorePatterns: ["*.log"]))
    }

    @Test func negativeFileSizeFailsClosed() {
        #expect(!ProjectFileIndexLogic.shouldIndex(relativePath: "src/a.swift", size: -1))
    }

    // MARK: - Delta

    private func rec(_ path: String, hash: String, mtime: TimeInterval = 1) -> FileIndexRecord {
        FileIndexRecord(path: path, hash: hash, size: 10, lastModified: mtime, language: "swift")
    }

    @Test func deltaDetectsNewFiles() {
        let delta = ProjectFileIndexLogic.computeDelta(
            current: [rec("a.swift", hash: "h1")],
            scanned: [rec("a.swift", hash: "h1"), rec("b.swift", hash: "h2")]
        )
        #expect(delta.toUpsert.map { $0.path } == ["b.swift"])
        #expect(delta.toRemove.isEmpty)
    }

    @Test func deltaDetectsChangedByHash() {
        let delta = ProjectFileIndexLogic.computeDelta(
            current: [rec("a.swift", hash: "h1")],
            scanned: [rec("a.swift", hash: "CHANGED")]
        )
        #expect(delta.toUpsert.count == 1)
        #expect(delta.toUpsert.first?.hash == "CHANGED")
    }

    @Test func deltaDetectsChangedByMtime() {
        let delta = ProjectFileIndexLogic.computeDelta(
            current: [rec("a.swift", hash: "h1", mtime: 1)],
            scanned: [rec("a.swift", hash: "h1", mtime: 999)]
        )
        #expect(delta.toUpsert.count == 1)
    }

    @Test func deltaSkipsUnchanged() {
        let delta = ProjectFileIndexLogic.computeDelta(
            current: [rec("a.swift", hash: "h1", mtime: 5)],
            scanned: [rec("a.swift", hash: "h1", mtime: 5)]
        )
        #expect(delta.toUpsert.isEmpty)
        #expect(delta.toRemove.isEmpty)
    }

    @Test func deltaDetectsRemovedFiles() {
        let delta = ProjectFileIndexLogic.computeDelta(
            current: [rec("a.swift", hash: "h1"), rec("gone.swift", hash: "h2")],
            scanned: [rec("a.swift", hash: "h1")]
        )
        #expect(delta.toRemove == ["gone.swift"])
    }

    // MARK: - Language + status

    @Test func languageInference() {
        #expect(ProjectFileIndexLogic.language(forExtension: "swift") == "swift")
        #expect(ProjectFileIndexLogic.language(forExtension: "TS") == "typescript")
        #expect(ProjectFileIndexLogic.language(forExtension: "") == "text")
    }

    @Test func indexStatusLabels() {
        #expect(ProjectIndexStatus.indexing(done: 12, total: 45).label == "Indexing: 12/45 files")
        #expect(ProjectIndexStatus.upToDate(fileCount: 300).label == "Up to date (300 files)")
    }
}
