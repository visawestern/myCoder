import Testing
import Foundation
@testable import myCoder

@Suite("Skill/MCP registry persistence (plan Раздел 3/4 Блок 1)")
struct AgentResourceRegistryManagerTests {

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Skills registry

    @Test func skillRegistryStartsEmpty() throws {
        let home = try makeTempHome()
        #expect(SkillRegistryManager.load(homeDirectory: home).isEmpty)
    }

    @Test func skillUpsertCreatesAndUpdatesRecord() throws {
        let home = try makeTempHome()
        let record = InstalledSkillRecord(id: "lazyweb", version: "1.0.0",
                                          installedAt: Date(), source: "mimo",
                                          isEnabled: true, path: "/skills/lazyweb")
        try SkillRegistryManager.upsert(record, homeDirectory: home)
        #expect(SkillRegistryManager.load(homeDirectory: home).count == 1)

        var updated = record
        updated.version = "1.1.0"
        try SkillRegistryManager.upsert(updated, homeDirectory: home)
        let loaded = SkillRegistryManager.load(homeDirectory: home)
        #expect(loaded.count == 1)
        #expect(loaded.first?.version == "1.1.0")
    }

    @Test func skillRegistryDeduplicatesCorruptedDuplicateIDs() throws {
        let home = try makeTempHome()
        let first = InstalledSkillRecord(id: "duplicate", version: "1.0.0",
                                         installedAt: Date(timeIntervalSince1970: 1), source: "mimo",
                                         isEnabled: true, path: "/old")
        let last = InstalledSkillRecord(id: "duplicate", version: "2.0.0",
                                        installedAt: Date(timeIntervalSince1970: 2), source: "cursor",
                                        isEnabled: false, path: "/new")
        try SkillRegistryManager.save([first, last], homeDirectory: home)
        let loaded = SkillRegistryManager.load(homeDirectory: home)
        #expect(loaded.count == 1)
        #expect(loaded.first?.version == "2.0.0")
        #expect(loaded.first?.path == "/new")
    }

    @Test func skillSetEnabledTogglesFlag() throws {
        let home = try makeTempHome()
        let record = InstalledSkillRecord(id: "canvas", version: "1.0.0",
                                          installedAt: Date(), source: "mimo",
                                          isEnabled: true, path: "/x")
        try SkillRegistryManager.upsert(record, homeDirectory: home)
        try SkillRegistryManager.setEnabled(id: "canvas", enabled: false, homeDirectory: home)
        let loaded = SkillRegistryManager.load(homeDirectory: home)
        #expect(loaded.first?.isEnabled == false)
    }

    @Test func skillSetEnabledReturnsFalseForMissingId() throws {
        let home = try makeTempHome()
        let ok = try SkillRegistryManager.setEnabled(id: "nope", enabled: true, homeDirectory: home)
        #expect(!ok)
    }

    @Test func skillRemoveDeletesRecord() throws {
        let home = try makeTempHome()
        let record = InstalledSkillRecord(id: "todo", version: "1.0.0",
                                          installedAt: Date(), source: "cursor",
                                          isEnabled: true, path: "/x")
        try SkillRegistryManager.upsert(record, homeDirectory: home)
        let removed = try SkillRegistryManager.remove(id: "todo", homeDirectory: home)
        #expect(removed)
        #expect(SkillRegistryManager.load(homeDirectory: home).isEmpty)
    }

    @Test func skillRemoveReturnsFalseForMissingId() throws {
        let home = try makeTempHome()
        let removed = try SkillRegistryManager.remove(id: "ghost", homeDirectory: home)
        #expect(!removed)
    }

    @Test func skillUpdateAvailableDetectsVersionMismatch() throws {
        let home = try makeTempHome()
        let record = InstalledSkillRecord(id: "lazyweb", version: "1.0.0",
                                          installedAt: Date(), source: "mimo",
                                          isEnabled: true, path: "/x")
        try SkillRegistryManager.upsert(record, homeDirectory: home)
        #expect(SkillRegistryManager.updateAvailable(for: "lazyweb", catalogVersion: "1.2.0", homeDirectory: home))
        #expect(!SkillRegistryManager.updateAvailable(for: "lazyweb", catalogVersion: "1.0.0", homeDirectory: home))
        #expect(!SkillRegistryManager.updateAvailable(for: "missing", catalogVersion: "1.0.0", homeDirectory: home))
    }

    // MARK: - MCP registry

    @Test func mcpRegistryStartsEmpty() throws {
        let home = try makeTempHome()
        #expect(MCPRegistryManager.load(homeDirectory: home).isEmpty)
    }

    @Test func mcpUpsertCreatesAndUpdatesRecord() throws {
        let home = try makeTempHome()
        let record = InstalledMCPRecord(id: "playwright", version: "1.0.0",
                                        installedAt: Date(), source: .mimo,
                                        isEnabled: true, transport: .stdio,
                                        lastHealthCheck: nil, lastHealthStatus: nil)
        try MCPRegistryManager.upsert(record, homeDirectory: home)
        #expect(MCPRegistryManager.load(homeDirectory: home).count == 1)

        var updated = record
        updated.isEnabled = false
        try MCPRegistryManager.upsert(updated, homeDirectory: home)
        #expect(MCPRegistryManager.load(homeDirectory: home).first?.isEnabled == false)
    }

    @Test func mcpRegistryDeduplicatesCorruptedDuplicateIDs() throws {
        let home = try makeTempHome()
        let first = InstalledMCPRecord(id: "duplicate", version: "1.0.0",
                                       installedAt: Date(timeIntervalSince1970: 1), source: .mimo,
                                       isEnabled: true, transport: .stdio,
                                       lastHealthCheck: nil, lastHealthStatus: nil)
        let last = InstalledMCPRecord(id: "duplicate", version: "2.0.0",
                                      installedAt: Date(timeIntervalSince1970: 2), source: .cursor,
                                      isEnabled: false, transport: .http,
                                      lastHealthCheck: nil, lastHealthStatus: false)
        try MCPRegistryManager.save([first, last], homeDirectory: home)
        let loaded = MCPRegistryManager.load(homeDirectory: home)
        #expect(loaded.count == 1)
        #expect(loaded.first?.version == "2.0.0")
        #expect(loaded.first?.transport == .http)
    }

    @Test func mcpSetEnabledTogglesFlag() throws {
        let home = try makeTempHome()
        let record = InstalledMCPRecord(id: "figma", version: "1.0.0",
                                        installedAt: Date(), source: .cursor,
                                        isEnabled: true, transport: .stdio,
                                        lastHealthCheck: nil, lastHealthStatus: nil)
        try MCPRegistryManager.upsert(record, homeDirectory: home)
        try MCPRegistryManager.setEnabled(id: "figma", enabled: false, homeDirectory: home)
        #expect(MCPRegistryManager.load(homeDirectory: home).first?.isEnabled == false)
    }

    @Test func mcpRemoveDeletesRecord() throws {
        let home = try makeTempHome()
        let record = InstalledMCPRecord(id: "git", version: "1.0.0",
                                        installedAt: Date(), source: .mimo,
                                        isEnabled: true, transport: .stdio,
                                        lastHealthCheck: nil, lastHealthStatus: nil)
        try MCPRegistryManager.upsert(record, homeDirectory: home)
        let removed = try MCPRegistryManager.remove(id: "git", homeDirectory: home)
        #expect(removed)
        #expect(MCPRegistryManager.load(homeDirectory: home).isEmpty)
    }

    @Test func mcpUpdateHealthCheckRecordsDate() throws {
        let home = try makeTempHome()
        let record = InstalledMCPRecord(id: "github", version: "1.0.0",
                                        installedAt: Date(), source: .mimo,
                                        isEnabled: true, transport: .stdio,
                                        lastHealthCheck: nil, lastHealthStatus: nil)
        try MCPRegistryManager.upsert(record, homeDirectory: home)
        let checkDate = Date()
        try MCPRegistryManager.updateHealthCheck(id: "github", at: checkDate, homeDirectory: home)
        let loaded = MCPRegistryManager.load(homeDirectory: home)
        #expect(loaded.first?.lastHealthCheck != nil)
    }
}
