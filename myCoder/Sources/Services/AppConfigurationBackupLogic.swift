import Foundation

struct AppConfigurationBackupBundle: Codable, Equatable {
    let schemaVersion: Int
    let exportedAt: Date
    let registryJSON: Data
    let settingsJSON: Data
}

enum AppConfigurationBackupLogic {
    static let currentSchemaVersion = 1

    static func encode(
        registryJSON: Data,
        settingsJSON: Data,
        exportedAt: Date = Date()
    ) -> Data? {
        let bundle = AppConfigurationBackupBundle(
            schemaVersion: currentSchemaVersion,
            exportedAt: exportedAt,
            registryJSON: registryJSON,
            settingsJSON: settingsJSON
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(bundle)
    }

    static func decode(data: Data) -> AppConfigurationBackupBundle? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(AppConfigurationBackupBundle.self, from: data),
              bundle.schemaVersion == currentSchemaVersion else { return nil }
        return bundle
    }
}
