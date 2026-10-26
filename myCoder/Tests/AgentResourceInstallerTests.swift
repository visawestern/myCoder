import Foundation
import Testing
@testable import myCoder

@Suite("Agent resource catalog and installer")
struct AgentResourceInstallerTests {
    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-agent-resources-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let sampleCatalogJSON = """
    {
      "version": 1,
      "updatedAt": "2026-06-21",
      "skills": [
        {
          "id": "demo-skill",
          "name": "Demo Skill",
          "description": "A demo skill for tests.",
          "category": "Test",
          "embeddedMarkdown": "---\\nname: demo-skill\\ndescription: Demo\\n---\\n# Demo"
        }
      ],
      "mcpServers": [
        {
          "id": "demo-mcp",
          "name": "Demo MCP",
          "description": "Demo MCP server.",
          "category": "Test",
          "url": "https://example.com/mcp"
        },
        {
          "id": "cmd-mcp",
          "name": "Command MCP",
          "description": "Command-based MCP.",
          "category": "Test",
          "command": "npx",
          "args": ["-y", "demo-server", "{HOME}"]
        }
      ]
    }
    """

    @Test func catalogDecodesSkillsAndMCPServers() throws {
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        #expect(catalog.skills.count == 1)
        #expect(catalog.mcpServers.count == 2)
        #expect(catalog.skills[0].id == "demo-skill")
    }

    @Test func filterCatalogItemsByQuery() throws {
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let filtered = AgentResourceLibraryLogic.filterSkills(catalog.skills, query: "demo")
        #expect(filtered.count == 1)
        #expect(AgentResourceLibraryLogic.filterMCPServers(catalog.mcpServers, query: "command").count == 1)
        #expect(AgentResourceLibraryLogic.filterSkills(catalog.skills, query: "missing").isEmpty)
    }

    @Test func isSkillInstalledChecksMiMoAndCursorPaths() throws {
        let home = try makeTempHome()
        let skillRoot = home.appendingPathComponent(".mycoder/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: skillRoot, withIntermediateDirectories: true)
        try "# Demo".write(to: skillRoot.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        #expect(AgentResourceLibraryLogic.isSkillInstalled(id: "demo", homeDirectory: home))
        #expect(!AgentResourceLibraryLogic.isSkillInstalled(id: "other", homeDirectory: home))
    }

    @Test func isMCPInstalledChecksMyCoderConfig() throws {
        let home = try makeTempHome()
        let configDir = home.appendingPathComponent(".mycoder", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let json = """
        {"mcpServers":{"lazyweb":{"url":"https://www.lazyweb.com/mcp"}}}
        """
        try json.write(to: configDir.appendingPathComponent("mcp.json"), atomically: true, encoding: .utf8)

        #expect(AgentResourceLibraryLogic.isMCPInstalled(id: "lazyweb", homeDirectory: home))
        #expect(!AgentResourceLibraryLogic.isMCPInstalled(id: "missing", homeDirectory: home))
    }

    @Test func installSkillWritesToMiMoSkillsDirectory() throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())

        try installer.installSkill(catalog.skills[0], bundle: AgentResourceCatalog.catalogBundle, homeDirectory: home)

        let skillFile = home.appendingPathComponent(".mycoder/skills/demo-skill/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: skillFile.path))
        let contents = try String(contentsOf: skillFile, encoding: .utf8)
        #expect(contents.contains("name: demo-skill"))
        #expect(AgentResourceLibraryLogic.isSkillInstalled(id: "demo-skill", homeDirectory: home))
    }

    @Test func installSkillIsIdempotent() throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())
        let item = catalog.skills[0]

        try installer.installSkill(item, bundle: AgentResourceCatalog.catalogBundle, homeDirectory: home)
        try installer.installSkill(item, bundle: AgentResourceCatalog.catalogBundle, homeDirectory: home)

        let skillFile = home.appendingPathComponent(".mycoder/skills/demo-skill/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: skillFile.path))
    }

    @Test func installMCPServerMergesIntoMiMoConfig() async throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())

        try await installer.installMCPServer(catalog.mcpServers[0], homeDirectory: home)

        let configURL = home.appendingPathComponent(".mycoder/mcp.json")
        let data = try Data(contentsOf: configURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let servers = json?["mcpServers"] as? [String: Any]
        let demo = servers?["demo-mcp"] as? [String: Any]
        #expect(demo?["url"] as? String == "https://example.com/mcp")
        #expect(AgentResourceLibraryLogic.isMCPInstalled(id: "demo-mcp", homeDirectory: home))
    }

    @Test func installMCPServerPreservesExistingEntries() async throws {
        let home = try makeTempHome()
        let mimocodeDir = home.appendingPathComponent(".mycoder", isDirectory: true)
        try FileManager.default.createDirectory(at: mimocodeDir, withIntermediateDirectories: true)
        let existing = """
        {"mcpServers":{"existing":{"url":"https://keep.me/mcp"}}}
        """
        try existing.write(to: mimocodeDir.appendingPathComponent("mcp.json"), atomically: true, encoding: .utf8)

        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())
        try await installer.installMCPServer(catalog.mcpServers[0], homeDirectory: home)

        let data = try Data(contentsOf: mimocodeDir.appendingPathComponent("mcp.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let servers = json?["mcpServers"] as? [String: Any]
        #expect(servers?["existing"] != nil)
        #expect(servers?["demo-mcp"] != nil)
    }

    @Test func installCommandMCPServerSubstitutesHomePlaceholder() async throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())

        try await installer.installMCPServer(catalog.mcpServers[1], homeDirectory: home)

        let data = try Data(contentsOf: home.appendingPathComponent(".mycoder/mcp.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let servers = json?["mcpServers"] as? [String: Any]
        let cmd = servers?["cmd-mcp"] as? [String: Any]
        let args = cmd?["args"] as? [String]
        #expect(cmd?["command"] as? String == "npx")
        #expect(args?.last == home.path)
    }

    @Test func installMCPServerAddsBearerTokenWhenFetcherReturnsToken() async throws {
        let home = try makeTempHome()
        let catalogJSON = """
        {
          "version": 1,
          "updatedAt": "2026-06-21",
          "skills": [],
          "mcpServers": [
            {
              "id": "token-mcp",
              "name": "Token MCP",
              "description": "Needs token.",
              "category": "Test",
              "url": "https://example.com/mcp",
              "fetchInstallToken": {
                "url": "https://example.com/token",
                "method": "POST",
                "body": "{}",
                "tokenKeys": ["token"]
              }
            }
          ]
        }
        """
        let catalog = try AgentResourceCatalog.load(from: Data(catalogJSON.utf8))
        let fetcher = StubMCPTokenFetcher(token: "test-token-123")
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: fetcher)

        try await installer.installMCPServer(catalog.mcpServers[0], homeDirectory: home)

        let data = try Data(contentsOf: home.appendingPathComponent(".mycoder/mcp.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let servers = json?["mcpServers"] as? [String: Any]
        let server = servers?["token-mcp"] as? [String: Any]
        let headers = server?["headers"] as? [String: String]
        #expect(headers?["Authorization"] == "Bearer test-token-123")
    }

    @Test func bundledCatalogLoadsFromAppBundle() throws {
        AgentResourceCatalog.catalogBundle = Bundle.module
        let catalog = try AgentResourceCatalog.loadBundled()
        #expect(!catalog.skills.isEmpty)
        #expect(!catalog.mcpServers.isEmpty)
        #expect(catalog.skills.contains { $0.id == "lazyweb" })
        #expect(catalog.mcpServers.contains { $0.id == "lazyweb" })
    }

    // MARK: - Expanded catalog (plan Раздел 3/4 Блок 3 — максимальный каталог)

    @Test func bundledCatalogHasAtLeast45Skills() throws {
        AgentResourceCatalog.catalogBundle = Bundle.module
        let catalog = try AgentResourceCatalog.loadBundled()
        #expect(catalog.skills.count >= 45)
    }

    @Test func bundledCatalogHasAtLeast25MCPServers() throws {
        AgentResourceCatalog.catalogBundle = Bundle.module
        let catalog = try AgentResourceCatalog.loadBundled()
        #expect(catalog.mcpServers.count >= 25)
    }

    @Test func bundledCatalogHasBrowserAndDesignMCPServers() throws {
        AgentResourceCatalog.catalogBundle = Bundle.module
        let catalog = try AgentResourceCatalog.loadBundled()
        let browser = catalog.mcpServers.filter { $0.category == "Browser Automation" }
        let design = catalog.mcpServers.filter { $0.category == "Design" }
        #expect(browser.count >= 3)
        #expect(design.count >= 2)
        #expect(catalog.mcpServers.contains { $0.id == "playwright" })
        #expect(catalog.mcpServers.contains { $0.id == "figma" })
    }

    @Test func catalogSkillItemDecodesOptionalMetadataFields() throws {
        let json = """
        {
          "version": 2, "updatedAt": "2026-07-23",
          "skills": [{
            "id": "s", "name": "S", "description": "d", "category": "c",
            "version": "1.2.0", "dependencies": ["node>=18", "playwright-mcp"],
            "sourceRepo": "anthropics/skills", "relatedMCPIds": ["p"]
          }],
          "mcpServers": []
        }
        """
        let catalog = try AgentResourceCatalog.load(from: Data(json.utf8))
        let s = catalog.skills[0]
        #expect(s.version == "1.2.0")
        #expect(s.dependencyIDs == ["node>=18", "playwright-mcp"])
        #expect(s.sourceRepo == "anthropics/skills")
        #expect(s.relatedMCPIDs == ["p"])
    }

    @Test func catalogMCPServerItemDecodesEnvHeadersTransportRequires() throws {
        let json = """
        {
          "version": 2, "updatedAt": "2026-07-23", "skills": [],
          "mcpServers": [{
            "id": "m", "name": "M", "description": "d", "category": "c",
            "command": "npx", "args": ["-y", "x"], "env": {"K": "v"},
            "headers": {"X-Test": "1"}, "transport": "stdio", "version": "1.0.0",
            "requires": ["node>=18"], "sourceRepo": "modelcontextprotocol/servers"
          }]
        }
        """
        let catalog = try AgentResourceCatalog.load(from: Data(json.utf8))
        let m = catalog.mcpServers[0]
        #expect(m.env?["K"] == "v")
        #expect(m.headers?["X-Test"] == "1")
        #expect(m.transportKind == "stdio")
        #expect(m.requirementIDs == ["node>=18"])
        #expect(m.version == "1.0.0")
    }

    @Test func installSkillRecordsInRegistry() throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())
        try installer.installSkill(catalog.skills[0], bundle: AgentResourceCatalog.catalogBundle, homeDirectory: home)

        let records = SkillRegistryManager.load(homeDirectory: home)
        #expect(records.count == 1)
        #expect(records.first?.id == "demo-skill")
        #expect(records.first?.isEnabled == true)
    }

    @Test func uninstallSkillRemovesRegistryRecord() throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())
        try installer.installSkill(catalog.skills[0], bundle: AgentResourceCatalog.catalogBundle, homeDirectory: home)
        try installer.uninstallSkill(catalog.skills[0], homeDirectory: home)
        #expect(SkillRegistryManager.load(homeDirectory: home).isEmpty)
    }

    @Test func installMCPServerRecordsInRegistry() async throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())
        try await installer.installMCPServer(catalog.mcpServers[0], homeDirectory: home)

        let records = MCPRegistryManager.load(homeDirectory: home)
        #expect(records.contains { $0.id == "demo-mcp" })
    }

    @Test func uninstallMCPServerRemovesRegistryRecord() async throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())
        try await installer.installMCPServer(catalog.mcpServers[0], homeDirectory: home)
        try installer.uninstallMCPServer(catalog.mcpServers[0], homeDirectory: home)
        #expect(!MCPRegistryManager.load(homeDirectory: home).contains { $0.id == "demo-mcp" })
    }

    @Test func installMCPServerWritesCatalogEnvAndHeaders() async throws {
        let home = try makeTempHome()
        let json = """
        {
          "version": 2, "updatedAt": "2026-07-23", "skills": [],
          "mcpServers": [{
            "id": "env-mcp", "name": "Env MCP", "description": "d", "category": "c",
            "command": "npx", "args": ["-y", "x"],
            "env": {"FOO": "bar"}, "headers": {"X-Custom": "yes"}
          }]
        }
        """
        let catalog = try AgentResourceCatalog.load(from: Data(json.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())
        try await installer.installMCPServer(catalog.mcpServers[0], homeDirectory: home)

        let data = try Data(contentsOf: home.appendingPathComponent(".mycoder/mcp.json"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let server = (root?["mcpServers"] as? [String: Any])?["env-mcp"] as? [String: Any]
        #expect((server?["env"] as? [String: String])?["FOO"] == "bar")
        #expect((server?["headers"] as? [String: String])?["X-Custom"] == "yes")
    }

    @Test func installBundledLazywebSkillFromCatalog() throws {
        AgentResourceCatalog.catalogBundle = Bundle.module
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.loadBundled()
        guard let lazyweb = catalog.skills.first(where: { $0.id == "lazyweb" }) else {
            Issue.record("Lazyweb skill missing from bundled catalog.")
            return
        }
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())
        try installer.installSkill(lazyweb, bundle: AgentResourceCatalog.catalogBundle, homeDirectory: home)

        let skillFile = home.appendingPathComponent(".mycoder/skills/lazyweb/SKILL.md")
        let contents = try String(contentsOf: skillFile, encoding: .utf8)
        #expect(contents.contains("name: lazyweb"))
    }

    // MARK: - Uninstall tests (F07)

    @Test func uninstallSkillRemovesDirectory() throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())

        try installer.installSkill(catalog.skills[0], bundle: AgentResourceCatalog.catalogBundle, homeDirectory: home)
        #expect(AgentResourceLibraryLogic.isSkillInstalled(id: "demo-skill", homeDirectory: home))

        try installer.uninstallSkill(catalog.skills[0], homeDirectory: home)
        #expect(!AgentResourceLibraryLogic.isSkillInstalled(id: "demo-skill", homeDirectory: home))
    }

    @Test func uninstallSkillThrowsIfNotInstalled() throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())

        #expect(throws: AgentResourceInstallError.self) {
            try installer.uninstallSkill(catalog.skills[0], homeDirectory: home)
        }
    }

    @Test func uninstallMCPServerRemovesFromConfig() async throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())

        try await installer.installMCPServer(catalog.mcpServers[0], homeDirectory: home)
        #expect(AgentResourceLibraryLogic.isMCPInstalled(id: "demo-mcp", homeDirectory: home))

        try installer.uninstallMCPServer(catalog.mcpServers[0], homeDirectory: home)
        #expect(!AgentResourceLibraryLogic.isMCPInstalled(id: "demo-mcp", homeDirectory: home))
    }

    @Test func uninstallMCPServerPreservesOtherServers() async throws {
        let home = try makeTempHome()
        let catalog = try AgentResourceCatalog.load(from: Data(sampleCatalogJSON.utf8))
        let installer = AgentResourceInstaller(fileManager: .default, tokenFetcher: StubMCPTokenFetcher())

        try await installer.installMCPServer(catalog.mcpServers[0], homeDirectory: home)
        try await installer.installMCPServer(catalog.mcpServers[1], homeDirectory: home)

        try installer.uninstallMCPServer(catalog.mcpServers[0], homeDirectory: home)

        let data = try Data(contentsOf: home.appendingPathComponent(".mycoder/mcp.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let servers = json?["mcpServers"] as? [String: Any]
        #expect(servers?["demo-mcp"] == nil)  // Removed
        #expect(servers?["cmd-mcp"] != nil)    // Preserved
    }
}

private struct StubMCPTokenFetcher: MCPTokenFetching {
    let token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func fetchToken(using spec: CatalogMCPTokenSpec) async throws -> String? {
        token
    }
}
