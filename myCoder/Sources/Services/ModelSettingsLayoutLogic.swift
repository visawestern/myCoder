import Foundation

enum ModelSettingsLayoutMode: Equatable {
    case compact
    case wide
}

enum ModelSettingsLayoutLogic {
    static let wideMinimumWidth: CGFloat = 760

    static func mode(availableWidth: CGFloat) -> ModelSettingsLayoutMode {
        availableWidth >= wideMinimumWidth ? .wide : .compact
    }
}
