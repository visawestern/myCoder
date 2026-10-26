import Foundation

enum AppConfigurationTransferLogic {
    enum Operation: Equatable {
        case export
        case `import`
    }

    enum Outcome: Equatable {
        case success
        case failure
    }

    struct Notice: Equatable, Identifiable {
        let outcome: Outcome
        let title: String
        let message: String

        var id: String { "\(title)|\(message)" }
    }

    static let importRequiresConfirmation = true

    static func notice(operation: Operation, succeeded: Bool) -> Notice {
        switch (operation, succeeded) {
        case (.export, true):
            return Notice(
                outcome: .success,
                title: "Configuration exported",
                message: "Your registry and settings were exported successfully."
            )
        case (.export, false):
            return Notice(
                outcome: .failure,
                title: "Configuration export failed",
                message: "myCoder could not write the configuration bundle. Check the selected location and try again."
            )
        case (.import, true):
            return Notice(
                outcome: .success,
                title: "Configuration imported",
                message: "Your registry and settings were imported successfully."
            )
        case (.import, false):
            return Notice(
                outcome: .failure,
                title: "Configuration import failed",
                message: "The bundle was rejected or could not be saved. Your current configuration was not refreshed."
            )
        }
    }
}
