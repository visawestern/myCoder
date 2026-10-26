import Testing
@testable import myCoder

@Suite("SET-04 skill uninstall safety")
struct SkillUninstallPolicyTests {
    @Test("confirmation identifies the skill and warns that uninstall is destructive")
    func confirmationCopyIsSpecific() {
        #expect(SkillUninstallPolicy.confirmationTitle(for: "Browser Skill") == "Uninstall Browser Skill?")
        #expect(SkillUninstallPolicy.confirmationMessage(for: "Browser Skill").contains("cannot be undone"))
    }
}
