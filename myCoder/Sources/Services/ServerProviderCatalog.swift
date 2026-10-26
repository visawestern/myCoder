import Foundation

/// Persisted snapshot of the OpenCode serve provider catalog plus the last
/// server address. Background work (internal models) runs without an AppState
/// reference, so it needs the catalog and endpoint to resolve server-provided
/// models after the app restarts.
enum ServerProviderCatalogStore {
    static let storageKey = "com.mycoder.serverProviders"
    static let hostKey = "com.mycoder.serverHost"
    static let portKey = "com.mycoder.serverPort"

    static func save(_ providers: [MimoProviderResponse], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load(defaults: UserDefaults = .standard) -> [MimoProviderResponse] {
        guard let data = defaults.data(forKey: storageKey),
              let providers = try? JSONDecoder().decode([MimoProviderResponse].self, from: data) else {
            return []
        }
        return providers
    }

    static func saveConnection(host: String, port: Int, defaults: UserDefaults = .standard) {
        defaults.set(host, forKey: hostKey)
        defaults.set(port, forKey: portKey)
    }

    static func serverBaseURL(defaults: UserDefaults = .standard) -> String {
        let host = defaults.string(forKey: hostKey).flatMap { $0.isEmpty ? nil : $0 } ?? "127.0.0.1"
        let port = defaults.object(forKey: portKey) as? Int ?? 4096
        return "http://\(host):\(port)"
    }
}
