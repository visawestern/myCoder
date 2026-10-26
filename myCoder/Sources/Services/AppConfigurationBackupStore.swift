import Foundation

enum AppConfigurationBackupStore {
    static func export(
        homeDirectory: URL,
        defaults: UserDefaults,
        to destination: URL,
        now: Date = Date()
    ) -> Bool {
        let registry = ProjectRegistryLogic.load(homeDirectory: homeDirectory)
        let settings = AppSettings.load(from: defaults)
        guard let registryJSON = try? encodeRegistry(registry),
              let settingsJSON = try? JSONEncoder().encode(settings),
              let data = AppConfigurationBackupLogic.encode(
                  registryJSON: registryJSON,
                  settingsJSON: settingsJSON,
                  exportedAt: now
              ) else { return false }
        do {
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func `import`(
        from source: URL,
        homeDirectory: URL,
        defaults: UserDefaults
    ) -> Bool {
        guard let data = try? Data(contentsOf: source),
              let bundle = AppConfigurationBackupLogic.decode(data: data),
              let registry = try? decodeRegistry(bundle.registryJSON),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: bundle.settingsJSON) else {
            return false
        }
        do {
            let normalizedRegistry = ProjectRegistryLogic.deduplicated(registry)
            try ProjectRegistryLogic.save(normalizedRegistry, homeDirectory: homeDirectory)
            settings.save(to: defaults)
            return true
        } catch {
            return false
        }
    }

    private static func encodeRegistry(_ entries: [ProjectRegistryEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ProjectRegistryDocument(projects: entries))
    }

    private static func decodeRegistry(_ data: Data) throws -> [ProjectRegistryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectRegistryDocument.self, from: data).projects
    }
}
