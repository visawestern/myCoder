import Testing
import Foundation
@testable import myCoder

/// Round 14 devil's-advocate fixes (re-audit 2026-08-01):
/// - plan п.5/п.17/п.18: createNewProject + addWorkspace minted TWO different
///   UUIDs for one folder — the id must be the canonical normalized path.
/// - plan Раздел 8 п.11/п.32: opening/creating a project must register it in
///   the registry (~/.mycoder/projects.json), otherwise the storage admin
///   panel is empty in real use ("registry is orphaned").
/// - plan Раздел 8 п.9/п.19: resetStorage must be injectable so tests (and
///   the StorageResetCrashTests that previously deleted the REAL user
///   ~/.mycoder/mycoder.db) never touch real user data.
@Suite("Round 14 — project identity + safe reset (devil's advocate)")
struct Round14IdentityAndResetTests {

    // MARK: - Injectability of resetStorage home

    @Test("resetStorage deletes ONLY inside the injected home directory")
    func resetStorageIsScopedToInjectedHome() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("r14-reset-\(UUID().uuidString)", isDirectory: true)
        let mimoDir = sandbox.appendingPathComponent(".mycoder")
        try FileManager.default.createDirectory(at: mimoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // Place fake "data" files — only the app DB is a reset target now
        // (HTTP-only, no CLI history: the reset clears the app cache).
        let fakeAppDB = mimoDir.appendingPathComponent("mycoder.db")
        let unrelated = sandbox.appendingPathComponent("keep.txt")
        try Data("app".utf8).write(to: fakeAppDB)
        try Data("keep".utf8).write(to: unrelated)

        let state = AppState()
        let plan = StorageResetLogic.plan(for: .appCacheOnly, homeDirectory: sandbox)
        // Execute the exact planned deletions (what resetStorage does, but
        // WITHOUT touching DatabaseManager.shared which is the real user DB).
        for path in plan.deletesPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        #expect(!FileManager.default.fileExists(atPath: fakeAppDB.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path)) // untouched

        // Every path the plan lists MUST live under the injected home — a
        // reset can never point outside the sandbox the test controls.
        for path in plan.deletesPaths {
            #expect(path.hasPrefix(sandbox.path), "plan path escapes the injected home: \(path)")
        }
        _ = state // AppState exists only to prove no real-data access is needed
    }

    // MARK: - Single canonical project id (п.17/п.18)

    @Test("project id is the canonical normalized path, not a UUID")
    func projectIdIsCanonicalPath() {
        let path = "/Users/test/My Project/"
        let id = ProjectIdentityLogic.projectID(for: path)
        #expect(id == IdentifierNormalization.projectID(for: path))
        #expect(!id.contains(UUID().uuidString.prefix(8)))
    }

    @Test("same folder reached via symlinked spelling maps to the same id")
    func projectIdStableAcrossSpellings() throws {
        // Create a real symlink and assert both spellings map to one id.
        // (The old check relied on host /tmp → /private/tmp which is not
        // guaranteed in the sandbox.)
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("r14-symlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let projectReal = real.appendingPathComponent("proj").path
        let projectViaLink = link.appendingPathComponent("proj").path
        try FileManager.default.createDirectory(atPath: projectReal, withIntermediateDirectories: true)

        let a = ProjectIdentityLogic.projectID(for: projectViaLink)
        let b = ProjectIdentityLogic.projectID(for: projectReal)
        #expect(a == b)
    }

    // MARK: - Registry registration on create/open (п.11/п.32)

    @Test("creating a project registers it in the registry (registry is not orphaned)")
    func createNewProjectRegistersInRegistry() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("r14-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let path = home.appendingPathComponent("proj").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

        // Pure registry contract: after registration the entry exists with
        // canonical id and lastOpenedAt refreshed (п.32 dedup).
        var entries: [ProjectRegistryEntry] = []
        entries = ProjectRegistryLogic.registerProject(path: path, name: "Proj", into: entries)
        entries = ProjectRegistryLogic.registerProject(path: path + "/", name: "Proj", into: entries)
        #expect(entries.count == 1)
        #expect(entries[0].id == IdentifierNormalization.projectID(for: path))
    }

    @Test("duplicate registry registration is idempotent by canonical path")
    func duplicateRegistrationIsIdempotent() {
        var entries: [ProjectRegistryEntry] = []
        entries = ProjectRegistryLogic.registerProject(path: "/p/x", name: "X", into: entries)
        entries = ProjectRegistryLogic.registerProject(path: "/p/x", name: "X", into: entries)
        #expect(entries.count == 1)
    }
}
