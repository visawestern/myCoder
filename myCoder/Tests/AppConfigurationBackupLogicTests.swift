import Foundation
import Testing
@testable import myCoder

@Suite("Registry and settings backup")
struct AppConfigurationBackupLogicTests {
    @Test("backup round-trips both registry and settings payloads")
    func roundTrip() throws {
        let registry = Data("registry".utf8)
        let settings = Data("settings".utf8)
        let data = try #require(AppConfigurationBackupLogic.encode(
            registryJSON: registry,
            settingsJSON: settings,
            exportedAt: Date(timeIntervalSince1970: 10)
        ))
        let bundle = try #require(AppConfigurationBackupLogic.decode(data: data))
        #expect(bundle.registryJSON == registry)
        #expect(bundle.settingsJSON == settings)
        #expect(bundle.schemaVersion == 1)
    }

    @Test("unsupported backup schema is rejected")
    func rejectsUnsupportedSchema() throws {
        let data = try JSONEncoder().encode(AppConfigurationBackupBundle(
            schemaVersion: 99,
            exportedAt: Date(timeIntervalSince1970: 10),
            registryJSON: Data("registry".utf8),
            settingsJSON: Data("settings".utf8)
        ))
        #expect(AppConfigurationBackupLogic.decode(data: data) == nil)
    }
}
