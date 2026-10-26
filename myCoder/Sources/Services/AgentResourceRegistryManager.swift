import Foundation

/// Persistent registry of installed skills' metadata (plan Раздел 3 Блок 1 п.10).
/// Stored at `~/.mycoder/skills/registry.json` because the filesystem scan
/// (AgentResourcesLoader.loadSkills) can't recover version/enabled/source.
struct InstalledSkillRecord: Codable, Identifiable, Equatable {
    let id: String
    var version: String
    var installedAt: Date
    var source: String          // "mimo" | "cursor"
    var isEnabled: Bool
    var path: String
}

struct SkillsRegistryDocument: Codable, Equatable {
    var skills: [InstalledSkillRecord]
}

enum SkillRegistryManager {
    static let registryRelativePath = MyCoderPaths.skillsRegistryRelativePath

    static func registryURL(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(registryRelativePath)
    }

    // MARK: - Read

    static func load(homeDirectory: URL, fileManager: FileManager = .default) -> [InstalledSkillRecord] {
        let url = registryURL(homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let doc = try? decoder.decode(SkillsRegistryDocument.self, from: data) else { return [] }
        var unique: [String: InstalledSkillRecord] = [:]
        for record in doc.skills {
            unique[record.id] = record
        }
        return unique.values.sorted { $0.id < $1.id }
    }

    // MARK: - Write

    static func save(_ records: [InstalledSkillRecord], homeDirectory: URL, fileManager: FileManager = .default) throws {
        let url = registryURL(homeDirectory: homeDirectory)
        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(SkillsRegistryDocument(skills: records))
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Mutations

    /// Upsert a record (create or update by id).
    static func upsert(_ record: InstalledSkillRecord, homeDirectory: URL, fileManager: FileManager = .default) throws {
        var records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
        } else {
            records.append(record)
        }
        try save(records, homeDirectory: homeDirectory, fileManager: fileManager)
    }

    /// Toggle enabled state for a skill (plan Блок 1 п.4).
    @discardableResult
    static func setEnabled(id: String, enabled: Bool, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return false }
        records[idx].isEnabled = enabled
        try save(records, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    /// Remove a record (plan Блок 1 п.6).
    @discardableResult
    static func remove(id: String, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return false }
        records.remove(at: idx)
        try save(records, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    /// Check if an update is available by comparing installed version vs catalog (plan Блок 1 п.7).
    static func updateAvailable(for id: String, catalogVersion: String, homeDirectory: URL, fileManager: FileManager = .default) -> Bool {
        let records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let record = records.first(where: { $0.id == id }) else { return false }
        return record.version != catalogVersion && !catalogVersion.isEmpty
    }
}

/// Persistent registry of installed MCP servers' metadata (plan Раздел 4 Блок 1 п.9).
/// Stored at `~/.mycoder/mcp/registry.json`.
struct InstalledMCPRecord: Codable, Identifiable, Equatable {
    enum Source: String, Codable { case mimo, cursor }
    enum Transport: String, Codable { case stdio, http }

    let id: String
    var version: String
    var installedAt: Date
    var source: Source
    var isEnabled: Bool
    var transport: Transport
    var lastHealthCheck: Date?
    var lastHealthStatus: Bool?
}

struct MCPRegistryDocument: Codable, Equatable {
    var servers: [InstalledMCPRecord]
}

enum MCPRegistryManager {
    static let registryRelativePath = MyCoderPaths.mcpRegistryRelativePath

    static func registryURL(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(registryRelativePath)
    }

    static func load(homeDirectory: URL, fileManager: FileManager = .default) -> [InstalledMCPRecord] {
        let url = registryURL(homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let doc = try? decoder.decode(MCPRegistryDocument.self, from: data) else { return [] }
        var unique: [String: InstalledMCPRecord] = [:]
        for record in doc.servers {
            unique[record.id] = record
        }
        return unique.values.sorted { $0.id < $1.id }
    }

    static func save(_ records: [InstalledMCPRecord], homeDirectory: URL, fileManager: FileManager = .default) throws {
        let url = registryURL(homeDirectory: homeDirectory)
        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(MCPRegistryDocument(servers: records))
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    static func upsert(_ record: InstalledMCPRecord, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
        } else {
            records.append(record)
        }
        try save(records, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    @discardableResult
    static func setEnabled(id: String, enabled: Bool, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return false }
        records[idx].isEnabled = enabled
        try save(records, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    @discardableResult
    static func remove(id: String, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return false }
        records.remove(at: idx)
        try save(records, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    @discardableResult
    static func updateHealthCheck(id: String, at date: Date, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return false }
        records[idx].lastHealthCheck = date
        try save(records, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    /// Persists the liveness result of the most recent real health check
    /// (E11). `status` is the outcome of an actual probe, so the Settings dot
    /// reflects health rather than the enabled preference.
    @discardableResult
    static func updateHealthStatus(id: String, status: Bool, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return false }
        records[idx].lastHealthStatus = status
        try save(records, homeDirectory: homeDirectory, fileManager: fileManager)
        return true
    }

    /// Whether a catalog version differs from the installed one (plan Раздел 4
    /// Блок 1 п.7) — surfaces the "Update" action in the library UI.
    static func updateAvailable(for id: String, catalogVersion: String, homeDirectory: URL, fileManager: FileManager = .default) -> Bool {
        let records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        guard let record = records.first(where: { $0.id == id }) else { return false }
        return record.version != catalogVersion && !catalogVersion.isEmpty
    }
}
