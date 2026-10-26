import Foundation

/// Pure classification for the stuck-I-beam cursor fix. AppKit exposes
/// SwiftUI buttons through accessibility roles/actions rather than NSButton,
/// so both signals are checked.
enum CursorHitLogic {
    static func isAction(role: String?, actionNames: [String]) -> Bool {
        if let role {
            switch role {
            case "AXButton", "AXLink", "AXMenuItem", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton":
                return true
            default:
                break
            }
        }
        return actionNames.contains("AXPress") || actionNames.contains("AXShowMenu")
    }
}
