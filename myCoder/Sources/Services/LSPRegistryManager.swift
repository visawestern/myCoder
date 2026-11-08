import Foundation

/// Persistent registry of installed language server (LSP) metadata.
/// Stored at `~/.mycoder/lsp/registry.json`, mirroring the MCP registry
/// (`~/.mycoder/mcp/registry.json`). Records version/source/enabled state so
/// the filesystem/discovery scan alone does not have to recover them.
struct InstalledLSPRecord: Codable, Identifiable, Equatable {
    enum Source: String, Codable { case mimo, cursor }

    let id: String
    var version: String
    var installedAt: Date
    var source: Source
    var isEnabled: Bool
    var command: String
    var args: [String]
    var languages: [String]
}

struct LSPRegistryDocument: Codable, Equatable {
    var servers: [InstalledLSPRecord]
}

enum LSPRegistryManager {
    static let registryRelativePath = MyCoderPaths.lspRegistryRelativePath

    static func registryURL(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(registryRelativePath)
    }

    static func load(homeDirectory: URL, fileManager: FileManager = .default) -> [InstalledLSPRecord] {
        let url = registryURL(homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let doc = try? decoder.decode(LSPRegistryDocument.self, from: data) else { return [] }
        var unique: [String: InstalledLSPRecord] = [:]
        for record in doc.servers {
            unique[record.id] = record
        }
        return unique.values.sorted { $0.id < $1.id }
    }

    static func save(_ records: [InstalledLSPRecord], homeDirectory: URL, fileManager: FileManager = .default) throws {
        let url = registryURL(homeDirectory: homeDirectory)
        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LSPRegistryDocument(servers: records))
        try data.write(to: url, options: .atomic)
    }

    /// Register a newly discovered/added server. Keeps prior enabled state.
    @discardableResult
    static func upsert(_ record: InstalledLSPRecord, homeDirectory: URL, fileManager: FileManager = .default) throws -> Bool {
        var records = load(homeDirectory: homeDirectory, fileManager: fileManager)
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            let previousEnabled = records[idx].isEnabled
            var updated = record
            updated.isEnabled = previousEnabled
            records[idx] = updated
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
}
