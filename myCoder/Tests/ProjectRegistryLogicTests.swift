import Testing
import Foundation
@testable import myCoder

@Suite("Project registry admin (plan Раздел 8 Блок 2/3)")
struct ProjectRegistryLogicTests {

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func entryIdIsCanonicalPath() {
        let a = ProjectRegistryEntry(path: "/home/u/proj/")
        let b = ProjectRegistryEntry(path: "/home/u/proj")
        #expect(a.id == b.id)      // trailing slash normalized → dedup works
        #expect(a.name == "proj")
    }

    @Test func upsertDeduplicatesSamePath() {
        var projects: [ProjectRegistryEntry] = []
        projects = ProjectRegistryLogic.upsert(ProjectRegistryEntry(path: "/p/x"), into: projects)
        projects = ProjectRegistryLogic.upsert(ProjectRegistryEntry(path: "/p/x/"), into: projects)
        #expect(projects.count == 1)   // reopening same folder does NOT duplicate
    }

    @Test func upsertPreservesArchiveState() {
        var e = ProjectRegistryEntry(path: "/p/x")
        e.archivedAt = Date()
        var projects = [e]
        projects = ProjectRegistryLogic.upsert(ProjectRegistryEntry(path: "/p/x"), into: projects)
        #expect(projects.first?.isArchived == true)          // archive preserved
    }

    @Test func archiveRestoreDeleteFlow() {
        var projects = [ProjectRegistryEntry(path: "/p/x")]
        let id = projects[0].id
        projects = ProjectRegistryLogic.archive(id: id, at: Date(), in: projects)
        #expect(projects[0].isArchived)
        #expect(ProjectRegistryLogic.active(projects).isEmpty)
        #expect(ProjectRegistryLogic.archived(projects).count == 1)

        projects = ProjectRegistryLogic.restore(id: id, in: projects)
        #expect(!projects[0].isArchived)

        projects = ProjectRegistryLogic.remove(id: id, in: projects)
        #expect(projects.isEmpty)
    }

    @Test func orphanedDetectsMissingPaths() throws {
        let home = try makeTempHome()
        let realDir = home.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        let projects = [
            ProjectRegistryEntry(path: realDir.path),
            ProjectRegistryEntry(path: "/definitely/missing/path")
        ]
        let orphans = ProjectRegistryLogic.orphaned(projects)
        #expect(orphans.count == 1)
        #expect(orphans.first?.path == "/definitely/missing/path")
    }

    @Test func removingOrphanedKeepsOnlyExistingFolders() throws {
        let home = try makeTempHome()
        let realDir = home.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        let projects = [
            ProjectRegistryEntry(path: realDir.path),
            ProjectRegistryEntry(path: "/definitely/missing/path")
        ]
        let cleaned = ProjectRegistryLogic.removingOrphaned(projects)
        #expect(cleaned.count == 1)
        #expect(cleaned.first?.path == realDir.path)
    }

    @Test func relinkRebindsOrphanToExistingPath() {
        // Plan Раздел 8 п.31: an orphaned project (folder moved/renamed) can be
        // re-linked to its new location — the record must keep its settings.
        let entry = ProjectRegistryEntry(path: "/old/path")
        let relinked = ProjectRegistryLogic.relink(entry, toNewPath: "/new/path")
        #expect(relinked.path == "/new/path")
        #expect(relinked.id == IdentifierNormalization.projectID(for: "/new/path"))
        #expect(relinked.name == "path")             // name refreshed from folder
    }

    @Test func relinkPreservesArchiveStatus() {
        var entry = ProjectRegistryEntry(path: "/old/path")
        entry.archivedAt = Date()
        let relinked = ProjectRegistryLogic.relink(entry, toNewPath: "/new/loc")
        #expect(relinked.isArchived)
        #expect(relinked.path == "/new/loc")
    }

    @Test func relinkNormalizesTrailingSlash() {
        let entry = ProjectRegistryEntry(path: "/old/path")
        let relinked = ProjectRegistryLogic.relink(entry, toNewPath: "/new/path/")
        #expect(relinked.path == "/new/path")
        #expect(relinked.id == IdentifierNormalization.projectID(for: "/new/path"))
    }

    @Test func inactiveLongerThanFilters() {
        let old = ProjectRegistryEntry(path: "/p/old", lastOpenedAt: Date().addingTimeInterval(-40 * 86400))
        let fresh = ProjectRegistryEntry(path: "/p/fresh", lastOpenedAt: Date())
        let inactive = ProjectRegistryLogic.inactiveLongerThan(days: 30, in: [old, fresh])
        #expect(inactive.count == 1)
        #expect(inactive.first?.name == "old")
    }

    @Test func persistenceRoundTrip() throws {
        let home = try makeTempHome()
        let projects = [
            ProjectRegistryEntry(path: "/p/a"),
            ProjectRegistryEntry(path: "/p/b")
        ]
        try ProjectRegistryLogic.save(projects, homeDirectory: home)
        let loaded = ProjectRegistryLogic.load(homeDirectory: home)
        #expect(loaded.count == 2)
        #expect(loaded.first(where: { $0.path == "/p/a" })?.name == "a")
    }

    @Test func activeSortedByLastOpened() {
        let a = ProjectRegistryEntry(path: "/p/a", lastOpenedAt: Date().addingTimeInterval(-100))
        let b = ProjectRegistryEntry(path: "/p/b", lastOpenedAt: Date())
        let active = ProjectRegistryLogic.active([a, b])
        #expect(active.first?.name == "b")   // most recent first
    }

    // MARK: - Plan Раздел 8 п.47: registry dedup on migration

    @Test func dedupMergesDuplicateEntriesByCanonicalPath() {
        // Legacy UUID-pileup: the old single DB stored several records for one
        // canonical path (plan Блок 1 п.4). Dedup must keep ONE record per path.
        let a = ProjectRegistryEntry(path: "/home/u/proj", name: "Proj",
                                     lastOpenedAt: Date(timeIntervalSince1970: 1000))
        let b = ProjectRegistryEntry(path: "/home/u/proj/", name: "Proj (2)",
                                     lastOpenedAt: Date(timeIntervalSince1970: 2000))
        let deduped = ProjectRegistryLogic.deduplicated([a, b])
        #expect(deduped.count == 1)
        #expect(deduped[0].id == IdentifierNormalization.projectID(for: "/home/u/proj"))
        // The most recently opened record wins the metadata.
        #expect(deduped[0].lastOpenedAt.timeIntervalSince1970 == 2000)
        #expect(deduped[0].name == "Proj (2)")
    }

    @Test func dedupPreservesArchiveStateAcrossDuplicates() {
        var a = ProjectRegistryEntry(path: "/p/x", lastOpenedAt: Date(timeIntervalSince1970: 100))
        a.archivedAt = Date(timeIntervalSince1970: 700)
        let b = ProjectRegistryEntry(path: "/p/x/", lastOpenedAt: Date(timeIntervalSince1970: 200))
        // Archive is a user decision; any duplicate being archived keeps it archived.
        let deduped = ProjectRegistryLogic.deduplicated([a, b])
        #expect(deduped.count == 1)
        #expect(deduped[0].archivedAt != nil)
    }

    @Test func dedupKeepsDistinctProjectsUntouched() {
        let a = ProjectRegistryEntry(path: "/p/one", lastOpenedAt: Date(timeIntervalSince1970: 100))
        let b = ProjectRegistryEntry(path: "/p/two", lastOpenedAt: Date(timeIntervalSince1970: 200))
        let c = ProjectRegistryEntry(path: "/p/three/", lastOpenedAt: Date(timeIntervalSince1970: 300))
        let deduped = ProjectRegistryLogic.deduplicated([a, b, c])
        #expect(deduped.count == 3)
    }

    @Test func dedupPreservesProviderAndModelFromNewest() {
        let a = ProjectRegistryEntry(path: "/p/x", lastOpenedAt: Date(timeIntervalSince1970: 100),
                                     defaultProviderID: "legacy", defaultModelID: "model-1")
        let b = ProjectRegistryEntry(path: "/p/x/", lastOpenedAt: Date(timeIntervalSince1970: 200),
                                     defaultProviderID: "new", defaultModelID: "model-2")
        let deduped = ProjectRegistryLogic.deduplicated([a, b])
        #expect(deduped[0].defaultProviderID == "new")
        #expect(deduped[0].defaultModelID == "model-2")
    }

    @Test func dedupMigrationRewritesRegistryFileOnce() throws {
        // End-to-end: a legacy registry file containing duplicates is rewritten
        // in place to a deduplicated document (idempotent on re-run).
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = [
            ProjectRegistryEntry(path: "/tmp/dup", name: "A", lastOpenedAt: Date(timeIntervalSince1970: 100)),
            ProjectRegistryEntry(path: "/tmp/dup/", name: "B", lastOpenedAt: Date(timeIntervalSince1970: 200))
        ]
        try ProjectRegistryLogic.save(legacy, homeDirectory: home)

        ProjectRegistryLogic.deduplicateRegistry(homeDirectory: home)
        let after = ProjectRegistryLogic.load(homeDirectory: home)
        #expect(after.count == 1)

        // Second run is a no-op (still one entry, no churn).
        ProjectRegistryLogic.deduplicateRegistry(homeDirectory: home)
        #expect(ProjectRegistryLogic.load(homeDirectory: home).count == 1)
    }
}
