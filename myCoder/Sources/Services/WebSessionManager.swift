import Foundation

/// Persists and restores one web-chat browser login session. Cookies and local
/// storage are kept in a provider/session-specific directory so accounts never
/// overwrite one another.
struct WebSessionStore: Codable, Equatable {
    var cookies: [BrowserCookie]
    var localStorage: [String: String]
    var savedAt: Date
}

struct WebStoredLoginSession: Codable, Equatable, Identifiable {
    let id: String
    let providerID: String
    var name: String
    let createdAt: Date
    var lastUsedAt: Date
    var store: WebSessionStore
}

enum WebSessionManager {
    static let defaultSessionID = "default"

    static func providerDirectory(providerId: String, homeDirectory: URL) -> URL {
        MyCoderPaths.webSessionsDir(providerId: providerId, homeDirectory: homeDirectory)
    }

    static func sessionDirectory(providerId: String,
                                 sessionID: String = defaultSessionID,
                                 homeDirectory: URL) -> URL {
        providerDirectory(providerId: providerId, homeDirectory: homeDirectory)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    static func storeURL(providerId: String,
                         homeDirectory: URL,
                         sessionID: String = defaultSessionID) -> URL {
        sessionDirectory(providerId: providerId, sessionID: sessionID, homeDirectory: homeDirectory)
            .appendingPathComponent("cookies.json")
    }

    private static func metadataURL(providerId: String,
                                    sessionID: String,
                                    homeDirectory: URL) -> URL {
        sessionDirectory(providerId: providerId, sessionID: sessionID, homeDirectory: homeDirectory)
            .appendingPathComponent("session.json")
    }

    static func persist(_ store: WebSessionStore,
                        providerId: String,
                        homeDirectory: URL,
                        sessionID: String = defaultSessionID,
                        sessionName: String? = nil,
                        fileManager: FileManager = .default) throws {
        let directory = sessionDirectory(providerId: providerId, sessionID: sessionID, homeDirectory: homeDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(store).write(to: storeURL(providerId: providerId,
                                                       homeDirectory: homeDirectory,
                                                       sessionID: sessionID), options: .atomic)

        let existing = restoreMetadata(providerId: providerId, sessionID: sessionID, homeDirectory: homeDirectory)
        let metadata = WebStoredLoginSession(
            id: sessionID,
            providerID: providerId,
            name: sessionName ?? existing?.name ?? (sessionID == defaultSessionID ? "Default login" : "Login \(sessionID.prefix(6))"),
            createdAt: existing?.createdAt ?? store.savedAt,
            lastUsedAt: Date(),
            store: store
        )
        try encoder.encode(metadata).write(to: metadataURL(providerId: providerId,
                                                            sessionID: sessionID,
                                                            homeDirectory: homeDirectory), options: .atomic)
    }

    static func restore(providerId: String,
                        homeDirectory: URL,
                        sessionID: String = defaultSessionID,
                        fileManager: FileManager = .default) -> WebSessionStore? {
        let url = storeURL(providerId: providerId, homeDirectory: homeDirectory, sessionID: sessionID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WebSessionStore.self, from: data)
    }

    static func restoreMetadata(providerId: String,
                                sessionID: String,
                                homeDirectory: URL,
                                fileManager: FileManager = .default) -> WebStoredLoginSession? {
        let url = metadataURL(providerId: providerId, sessionID: sessionID, homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WebStoredLoginSession.self, from: data)
    }

    static func list(providerId: String,
                     homeDirectory: URL,
                     fileManager: FileManager = .default) -> [WebStoredLoginSession] {
        let directory = providerDirectory(providerId: providerId, homeDirectory: homeDirectory)
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        var sessions: [WebStoredLoginSession] = []
        for name in names where !name.hasPrefix(".") {
            if let metadata = restoreMetadata(providerId: providerId, sessionID: name, homeDirectory: homeDirectory) {
                sessions.append(metadata)
            } else if let store = restore(providerId: providerId, homeDirectory: homeDirectory, sessionID: name) {
                sessions.append(WebStoredLoginSession(
                    id: name,
                    providerID: providerId,
                    name: name == defaultSessionID ? "Default login" : "Login \(name.prefix(6))",
                    createdAt: store.savedAt,
                    lastUsedAt: store.savedAt,
                    store: store
                ))
            }
        }
        return sessions.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    static func clear(providerId: String,
                      homeDirectory: URL,
                      sessionID: String? = nil,
                      fileManager: FileManager = .default) throws {
        let dir = sessionID.map {
            sessionDirectory(providerId: providerId, sessionID: $0, homeDirectory: homeDirectory)
        } ?? providerDirectory(providerId: providerId, homeDirectory: homeDirectory)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    /// True when the stored session is expired (all cookies past expiry).
    static func isExpired(_ store: WebSessionStore, now: Date = Date()) -> Bool {
        let expiries = store.cookies.compactMap { $0.expiresEpoch }
        return WebSessionLogic.isSessionExpired(cookieExpiryEpochs: expiries,
                                                now: now.timeIntervalSince1970)
    }
}
