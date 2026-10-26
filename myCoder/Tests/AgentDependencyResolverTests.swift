import Foundation
import Testing
@testable import myCoder

@Suite("Agent dependency resolver")
struct AgentDependencyResolverTests {

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-deps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sampleSkill(dependencies: [String]?) -> CatalogSkillItem {
        CatalogSkillItem(
            id: "dep-skill",
            name: "Dep Skill",
            description: "Skill with dependencies.",
            category: "Test",
            bundlePath: nil,
            embeddedMarkdown: "# Dep",
            relatedMCPIds: ["demo-mcp"],
            version: "1.0.0",
            dependencies: dependencies,
            sourceRepo: nil
        )
    }

    @Test func classifyRuntimeWithConstraint() {
        #expect(AgentDependencyResolver.classify("node>=18") == .runtime(binary: "node", constraint: ">=18"))
    }

    @Test func classifyBareRuntime() {
        #expect(AgentDependencyResolver.classify("python3") == .runtime(binary: "python3", constraint: nil))
    }

    @Test func classifyMCPSuffix() {
        #expect(AgentDependencyResolver.classify("playwright-mcp") == .mcp(serverID: "playwright"))
    }

    @Test func classifyKnownServerName() {
        #expect(AgentDependencyResolver.classify("figma") == .mcp(serverID: "figma"))
    }

    @Test func classifyUnknownNameAsRuntime() {
        // "docker" is not a known server id → treated as a runtime binary.
        #expect(AgentDependencyResolver.classify("docker") == .runtime(binary: "docker", constraint: nil))
    }

    @Test func resolveRuntimeSatisfiedByProbe() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let skill = sampleSkill(dependencies: ["node"])
        let results = AgentDependencyResolver.resolve(
            skill: skill,
            homeDirectory: home,
            checkBinary: { $0 == "node" }
        )
        #expect(results.count == 1)
        #expect(results[0].isSatisfied)
        #expect(results[0].detail.contains("node"))
    }

    @Test func resolveRuntimeUnsatisfied() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let skill = sampleSkill(dependencies: ["node"])
        let results = AgentDependencyResolver.resolve(
            skill: skill,
            homeDirectory: home,
            checkBinary: { _ in false }
        )
        #expect(results[0].isSatisfied == false)
        #expect(results[0].detail.contains("not found"))
    }

    @Test func resolveMCPSatisfiedWhenInstalled() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // Write a config so isMCPInstalled sees "demo" (the classifier strips "-mcp").
        let configURL = home.appendingPathComponent(".mycoder/mcp.json")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = Data("""
        {"mcpServers":{"demo":{"command":"x"}}}
        """.utf8)
        try payload.write(to: configURL)

        let skill = sampleSkill(dependencies: ["demo-mcp"])
        let results = AgentDependencyResolver.resolve(skill: skill, homeDirectory: home, checkBinary: { _ in false })
        #expect(results.count == 1)
        #expect(results[0].isSatisfied)
        #expect(results[0].detail.contains("installed"))
    }

    @Test func resolveMCPUnsatisfiedWhenAbsent() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let skill = sampleSkill(dependencies: ["playwright-mcp"])
        let results = AgentDependencyResolver.resolve(skill: skill, homeDirectory: home, checkBinary: { _ in false })
        #expect(results[0].isSatisfied == false)
        #expect(results[0].detail.contains("not installed"))
    }

    @Test func resolveServerUsesRequirementIDs() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let server = CatalogMCPServerItem(
            id: "demo-server",
            name: "Demo",
            description: "",
            category: "Test",
            url: nil,
            command: "node",
            args: nil,
            env: nil,
            headers: nil,
            transport: nil,
            fetchInstallToken: nil,
            version: nil,
            requires: ["node>=18"],
            sourceRepo: nil
        )
        let results = AgentDependencyResolver.resolve(server: server, homeDirectory: home, checkBinary: { _ in true })
        #expect(results.count == 1)
        #expect(results[0].isSatisfied)
        #expect(results[0].requirement == "node>=18")
    }

    @Test func liveProbeFindsBundledBinaries() {
        // Real-machine check (no mocks): `sh` is always present on POSIX/macOS.
        let present = AgentDependencyResolver.runtimeBinaryPresent("sh")
        #expect(present)
    }

    @Test func liveProbeRejectsMissingBinary() {
        let present = AgentDependencyResolver.runtimeBinaryPresent("definitely-not-a-real-binary-xyz")
        #expect(present == false)
    }
}
