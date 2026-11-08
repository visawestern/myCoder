import Foundation

enum LSPConfigMutationError: LocalizedError, Equatable {
    case invalidJSON
    case missingServersObject
    case targetMissing(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "LSP configuration is not valid JSON."
        case .missingServersObject: return "LSP configuration has no lspServers object."
        case .targetMissing(let id): return "LSP server \(id) is not present in the configuration."
        case .encodingFailed: return "LSP configuration could not be encoded."
        }
    }
}

/// Pure mutations on `~/.mycoder/lsp.json` — the on-disk config of installed
/// language servers. Mirrors `MCPConfigMutationLogic` so the UI behaves the
/// same for both resource types.
enum LSPConfigMutationLogic {

    static func decodeRoot(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LSPConfigMutationError.invalidJSON
        }
        return root
    }

    static func decodeServers(_ root: [String: Any]) throws -> [String: Any] {
        guard let servers = root["lspServers"] as? [String: Any] else {
            throw LSPConfigMutationError.missingServersObject
        }
        return servers
    }

    static func encodeRoot(_ root: [String: Any]) throws -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            throw LSPConfigMutationError.encodingFailed
        }
        return data
    }

    static func setDisabled(data: Data, id: String, disabled: Bool) throws -> Data {
        var root = try decodeRoot(data)
        var servers = try decodeServers(root)
        guard var entry = servers[id] as? [String: Any] else {
            throw LSPConfigMutationError.targetMissing(id)
        }
        if disabled {
            entry["disabled"] = true
        } else {
            entry.removeValue(forKey: "disabled")
        }
        servers[id] = entry
        root["lspServers"] = servers
        return try encodeRoot(root)
    }

    static func remove(data: Data, id: String) throws -> Data {
        var root = try decodeRoot(data)
        var servers = try decodeServers(root)
        guard servers.removeValue(forKey: id) != nil else {
            throw LSPConfigMutationError.targetMissing(id)
        }
        root["lspServers"] = servers
        return try encodeRoot(root)
    }

    /// Add or replace a custom language server spec.
    static func upsertServer(data: Data, id: String, command: String, args: [String], languages: [String]) throws -> Data {
        var root: [String: Any]
        if data.isEmpty {
            root = [:]
        } else {
            root = try decodeRoot(data)
        }
        var servers = root["lspServers"] as? [String: Any] ?? [:]
        var entry: [String: Any] = ["command": command]
        if !args.isEmpty { entry["args"] = args }
        if !languages.isEmpty { entry["languages"] = languages }
        servers[id] = entry
        root["lspServers"] = servers
        return try encodeRoot(root)
    }
}
