import Foundation

enum SkillUninstallPolicy {
    static func confirmationTitle(for skillName: String) -> String {
        "Uninstall \(skillName)?"
    }

    static func confirmationMessage(for skillName: String) -> String {
        "This removes \"\(skillName)\" from the installed skills directory and registry. This cannot be undone."
    }
}
