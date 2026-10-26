import Foundation

enum MCPConfigMutationError: LocalizedError, Equatable {
    case invalidJSON
    case missingServersObject
    case targetMissing(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "MCP configuration is not valid JSON."
        case .missingServersObject:
            return "MCP configuration has no mcpServers object."
        case .targetMissing(let id):
            return "MCP server \(id) is not present in the configuration."
        case .encodingFailed:
            return "MCP configuration could not be encoded."
        }
    }
}

enum MCPConfigMutationLogic {
    static func setDisabled(data: Data, id: String, disabled: Bool) throws -> Data {
        var root = try decodeRoot(data)
        var servers = try decodeServers(root)
        guard var entry = servers[id] as? [String: Any] else {
            throw MCPConfigMutationError.targetMissing(id)
        }
        entry["disabled"] = disabled
        servers[id] = entry
        root["mcpServers"] = servers
        return try encodeRoot(root)
    }

    static func remove(data: Data, id: String) throws -> Data {
        var root = try decodeRoot(data)
        var servers = try decodeServers(root)
        guard servers.removeValue(forKey: id) != nil else {
            throw MCPConfigMutationError.targetMissing(id)
        }
        root["mcpServers"] = servers
        return try encodeRoot(root)
    }

    private static func decodeRoot(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPConfigMutationError.invalidJSON
        }
        return root
    }

    private static func decodeServers(_ root: [String: Any]) throws -> [String: Any] {
        guard let servers = root["mcpServers"] as? [String: Any] else {
            throw MCPConfigMutationError.missingServersObject
        }
        return servers
    }

    private static func encodeRoot(_ root: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            throw MCPConfigMutationError.encodingFailed
        }
        return data
    }
}
