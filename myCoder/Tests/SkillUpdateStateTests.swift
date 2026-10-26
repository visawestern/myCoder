import Foundation
import Testing
@testable import myCoder

@Suite("SET-04 skill update state preservation")
struct SkillUpdateStateTests {
    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mycoder-skill-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func skill(version: String, markdown: String) -> CatalogSkillItem {
        CatalogSkillItem(
            id: "stateful-skill",
            name: "Stateful Skill",
            description: "Preserves enablement state.",
            category: "Test",
            bundlePath: nil,
            embeddedMarkdown: markdown,
            relatedMCPIds: nil,
            version: version,
            dependencies: nil,
            sourceRepo: nil
        )
    }

    @Test("updating a disabled skill preserves the disabled preference")
    func updatePreservesDisabledState() throws {
        let home = try makeTempHome()
        let installer = AgentResourceInstaller()
        try installer.installSkill(skill(version: "1.0.0", markdown: "old"), homeDirectory: home)
        #expect(try SkillRegistryManager.setEnabled(id: "stateful-skill", enabled: false, homeDirectory: home))

        try installer.updateSkill(skill(version: "2.0.0", markdown: "new"), homeDirectory: home)

        #expect(SkillRegistryManager.load(homeDirectory: home).first?.isEnabled == false)
        #expect(try String(contentsOf: home.appendingPathComponent(".mycoder/skills/stateful-skill/SKILL.md"), encoding: .utf8) == "new")
    }

    @Test("updating an enabled skill preserves the enabled preference")
    func updatePreservesEnabledState() throws {
        let home = try makeTempHome()
        let installer = AgentResourceInstaller()
        try installer.installSkill(skill(version: "1.0.0", markdown: "old"), homeDirectory: home)

        try installer.updateSkill(skill(version: "2.0.0", markdown: "new"), homeDirectory: home)

        #expect(SkillRegistryManager.load(homeDirectory: home).first?.isEnabled == true)
    }
}
