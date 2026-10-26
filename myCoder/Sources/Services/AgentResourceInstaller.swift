import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum AgentResourceInstallError: LocalizedError {
    case catalogMissing
    case skillSourceMissing(String)
    case tokenFetchFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .catalogMissing:
            return "Resource catalog is missing from the app bundle."
        case .skillSourceMissing(let id):
            return "Skill source is missing for \(id)."
        case .tokenFetchFailed(let message):
            return "Failed to fetch MCP install token: \(message)"
        case .writeFailed(let message):
            return "Failed to write resource files: \(message)"
        }
    }
}

protocol MCPTokenFetching {
    func fetchToken(using spec: CatalogMCPTokenSpec) async throws -> String?
}

struct LiveMCPTokenFetcher: MCPTokenFetching {
    func fetchToken(using spec: CatalogMCPTokenSpec) async throws -> String? {
        guard let url = URL(string: spec.url) else {
            throw AgentResourceInstallError.tokenFetchFailed("Invalid token URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = spec.method.uppercased()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !spec.body.isEmpty {
            request.httpBody = spec.body.data(using: .utf8)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.send(request)
        } catch {
            throw AgentResourceInstallError.tokenFetchFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AgentResourceInstallError.tokenFetchFailed("HTTP \(status)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentResourceInstallError.tokenFetchFailed("Invalid token response.")
        }

        for key in spec.tokenKeys {
            if let token = json[key] as? String, !token.isEmpty {
                return token
            }
        }
        throw AgentResourceInstallError.tokenFetchFailed("Token key not found.")
    }

    /// Cross-platform URLSession data fetch. Uses the async `data(for:)` API on
    /// Apple platforms and a continuation bridge elsewhere (Linux FoundationNetworking).
    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        return try await URLSession.shared.data(for: request)
        #else
        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, let response = response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
        #endif
    }
}

struct AgentResourceInstaller {
    let fileManager: FileManager
    let tokenFetcher: MCPTokenFetching

    init(fileManager: FileManager = .default, tokenFetcher: MCPTokenFetching = LiveMCPTokenFetcher()) {
        self.fileManager = fileManager
        self.tokenFetcher = tokenFetcher
    }

    func installSkill(
        _ item: CatalogSkillItem,
        bundle: Bundle = AgentResourceCatalog.catalogBundle,
        homeDirectory: URL
    ) throws {
        let previousEnabled = SkillRegistryManager.load(
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ).first { $0.id == item.id }?.isEnabled ?? true
        let markdown = try resolveSkillMarkdown(item, bundle: bundle)
        let skillDir = MyCoderPaths.skillDir(id: item.id, homeDirectory: homeDirectory)
        try fileManager.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        try markdown.write(to: skillFile, atomically: true, encoding: .utf8)

        // Record install metadata so the registry (not just a filesystem scan)
        // knows the installed version / enabled state / source (plan Раздел 3 Блок 1 п.10).
        let record = InstalledSkillRecord(
            id: item.id,
            version: item.version ?? "1.0.0",
            installedAt: Date(),
            source: "mimo",
            isEnabled: previousEnabled,
            path: skillFile.path
        )
        try SkillRegistryManager.upsert(record, homeDirectory: homeDirectory, fileManager: fileManager)
    }

    /// One-click dependency install (plan AGR-07): installs the skill plus any
    /// declared MCP-server dependencies that are missing. Runtime binaries that
    /// are absent are reported back (they cannot be provisioned by the app),
    /// while installable MCP dependencies are installed first, in dependency
    /// order, before the skill itself is written.
    func installSkillWithDependencies(
        _ item: CatalogSkillItem,
        catalog: AgentResourceCatalogDocument,
        bundle: Bundle = AgentResourceCatalog.catalogBundle,
        homeDirectory: URL
    ) async throws -> [String] {
        let results = AgentDependencyResolver.resolve(skill: item, homeDirectory: homeDirectory)
        var unresolved: [String] = []
        for result in results where !result.isSatisfied {
            switch result.kind {
            case .mcp(let serverID):
                if let server = catalog.mcpServers.first(where: { $0.id == serverID }) {
                    try await installMCPServer(server, homeDirectory: homeDirectory)
                } else {
                    unresolved.append(serverID)
                }
            case .runtime(let binary, _):
                unresolved.append(binary)
            }
        }
        try installSkill(item, bundle: bundle, homeDirectory: homeDirectory)
        return unresolved
    }

    func installMCPServer(_ item: CatalogMCPServerItem, homeDirectory: URL) async throws {
        var serverConfig: [String: Any] = [:]

        if let url = item.url {
            serverConfig["url"] = url
        }
        if let command = item.command {
            serverConfig["command"] = command
        }
        if let args = item.args {
            serverConfig["args"] = args.map { $0.replacingOccurrences(of: "{HOME}", with: homeDirectory.path) }
        }

        if let tokenSpec = item.fetchInstallToken {
            if let token = try await tokenFetcher.fetchToken(using: tokenSpec) {
                serverConfig["headers"] = ["Authorization": "Bearer \(token)"]
            }
        }
        // Merge any catalog-declared env/headers (token-derived Authorization wins
        // only when the catalog did not already set Authorization).
        if let env = item.env, !env.isEmpty {
            var merged = (serverConfig["env"] as? [String: String]) ?? [:]
            for (k, v) in env { merged[k] = v }
            serverConfig["env"] = merged
        }
        if let headers = item.headers, !headers.isEmpty {
            var merged = (serverConfig["headers"] as? [String: String]) ?? [:]
            for (k, v) in headers {
                if merged[k] == nil { merged[k] = v }
            }
            serverConfig["headers"] = merged
        }

        let configURL = MyCoderPaths.mcpConfigURL(homeDirectory: homeDirectory)
        var root: [String: Any] = [:]
        if fileManager.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }

        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[item.id] = serverConfig
        root["mcpServers"] = servers

        let configDir = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        do {
            try data.write(to: configURL, options: .atomic)
        } catch {
            throw AgentResourceInstallError.writeFailed(error.localizedDescription)
        }

        // Record install metadata in the MCP registry (plan Раздел 4 Блок 1 п.9).
        let record = InstalledMCPRecord(
            id: item.id,
            version: item.version ?? "1.0.0",
            installedAt: Date(),
            source: .mimo,
            isEnabled: true,
            transport: item.transportKind == "http" ? .http : .stdio,
            lastHealthCheck: nil,
            lastHealthStatus: nil
        )
        try MCPRegistryManager.upsert(record, homeDirectory: homeDirectory, fileManager: fileManager)
    }

    func uninstallSkill(_ item: CatalogSkillItem, homeDirectory: URL) throws {
        let skillDir = MyCoderPaths.skillDir(id: item.id, homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: skillDir.path) else {
            throw AgentResourceInstallError.writeFailed("Skill \(item.id) is not installed.")
        }
        try fileManager.removeItem(at: skillDir)
        _ = try SkillRegistryManager.remove(id: item.id, homeDirectory: homeDirectory, fileManager: fileManager)
    }

    /// Re-install an installed skill from the current catalog version, bumping
    /// the registry record's version (plan Раздел 3 Блок 1 п.5/п.7).
    func updateSkill(
        _ item: CatalogSkillItem,
        bundle: Bundle = AgentResourceCatalog.catalogBundle,
        homeDirectory: URL
    ) throws {
        guard SkillRegistryManager.updateAvailable(
            for: item.id,
            catalogVersion: item.version ?? "",
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ) else {
            // Nothing to update — silently keep the current install (idempotent).
            return
        }
        try installSkill(item, bundle: bundle, homeDirectory: homeDirectory)
    }

    /// Re-write an installed MCP server config from the current catalog version,
    /// bumping the registry record (plan Раздел 4 Блок 1 п.7).
    func updateMCPServer(_ item: CatalogMCPServerItem, homeDirectory: URL) async throws {
        guard MCPRegistryManager.updateAvailable(
            for: item.id,
            catalogVersion: item.version ?? "",
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ) else {
            return
        }
        try await installMCPServer(item, homeDirectory: homeDirectory)
    }

    func uninstallMCPServer(_ item: CatalogMCPServerItem, homeDirectory: URL) throws {
        let configURL = MyCoderPaths.mcpConfigURL(homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentResourceInstallError.writeFailed("MCP config not found.")
        }

        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        guard servers.removeValue(forKey: item.id) != nil else {
            throw AgentResourceInstallError.writeFailed("MCP server \(item.id) is not installed.")
        }
        root["mcpServers"] = servers

        let newData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        do {
            try newData.write(to: configURL, options: .atomic)
        } catch {
            throw AgentResourceInstallError.writeFailed(error.localizedDescription)
        }
        _ = try MCPRegistryManager.remove(id: item.id, homeDirectory: homeDirectory, fileManager: fileManager)
    }

    private func resolveSkillMarkdown(_ item: CatalogSkillItem, bundle: Bundle) throws -> String {
        if let embedded = item.embeddedMarkdown, !embedded.isEmpty {
            return embedded
        }
        if let bundlePath = item.bundlePath {
            let normalized = bundlePath.replacingOccurrences(of: "\\", with: "/")
            let components = normalized.split(separator: "/").map(String.init)
            guard let fileName = components.last else {
                throw AgentResourceInstallError.skillSourceMissing(item.id)
            }
            let subdirectory = components.dropLast().joined(separator: "/")
            let resourceName = (fileName as NSString).deletingPathExtension
            let fileExtension = (fileName as NSString).pathExtension
            let subdir = subdirectory.isEmpty ? nil : subdirectory
            guard let url = bundle.url(
                forResource: resourceName,
                withExtension: fileExtension.isEmpty ? nil : fileExtension,
                subdirectory: subdir
            ) ?? bundle.url(
                forResource: resourceName,
                withExtension: fileExtension.isEmpty ? nil : fileExtension
            ) else {
                throw AgentResourceInstallError.skillSourceMissing(item.id)
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        throw AgentResourceInstallError.skillSourceMissing(item.id)
    }
}
