import Foundation

enum AccessLevelPermissionLogic {
    static func permissionPatch(for level: AccessLevel) -> [String: Any] {
        switch level {
        case .askBeforeChanges:
            return ["edit": "ask"]
        case .editAutomatically:
            return ["edit": "allow"]
        case .fullAccess:
            return [
                "edit": "allow",
                "bash": "allow",
                "webfetch": "allow",
                "external_directory": "allow"
            ]
        }
    }

    static func accessLevel(from permission: [String: String]?) -> AccessLevel {
        guard let permission else { return .askBeforeChanges }
        let edit = permission["edit"]
        let bash = permission["bash"]
        if edit == "allow", bash == "allow" {
            return .fullAccess
        }
        if edit == "allow" {
            return .editAutomatically
        }
        return .askBeforeChanges
    }

    static func migrateLegacyAccessLevel(raw: String) -> AccessLevel {
        if raw == "Plan mode" {
            return .askBeforeChanges
        }
        return AccessLevel(rawValue: raw) ?? .askBeforeChanges
    }

    static func shouldSwitchToPlanAgent(legacyRaw: String) -> Bool {
        legacyRaw == "Plan mode"
    }
}
