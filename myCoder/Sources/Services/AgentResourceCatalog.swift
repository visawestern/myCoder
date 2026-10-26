import Foundation

struct CatalogMCPTokenSpec: Codable, Equatable {
    let url: String
    let method: String
    let body: String
    let tokenKeys: [String]
}

struct CatalogSkillItem: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let category: String
    let bundlePath: String?
    let embeddedMarkdown: String?
    let relatedMCPIds: [String]?
    /// Catalog version of this skill entry (semver-ish, e.g. "1.0.0").
    let version: String?
    /// Runtime/system dependency ids this skill needs (MCP ids and/or
    /// well-known requirement ids like "node>=18", "python3", "docker").
    let dependencies: [String]?
    /// Upstream source repository, e.g. "anthropics/skills".
    let sourceRepo: String?

    var relatedMCPIDs: [String] { relatedMCPIds ?? [] }
    var dependencyIDs: [String] { dependencies ?? [] }
}

struct CatalogMCPServerItem: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let category: String
    let url: String?
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let headers: [String: String]?
    /// Transport hint: "stdio" (default when command present) or "http".
    let transport: String?
    let fetchInstallToken: CatalogMCPTokenSpec?
    /// Catalog version of this MCP entry (semver-ish).
    let version: String?
    /// Runtime/system requirements, e.g. ["node>=18", "python3", "docker"].
    let requires: [String]?
    /// Upstream source repository, e.g. "modelcontextprotocol/servers".
    let sourceRepo: String?

    var transportKind: String { transport ?? (command == nil ? "http" : "stdio") }
    var requirementIDs: [String] { requires ?? [] }
}

struct AgentResourceCatalogDocument: Codable, Equatable {
    let version: Int
    let updatedAt: String
    let skills: [CatalogSkillItem]
    let mcpServers: [CatalogMCPServerItem]
}

enum AgentResourceCatalog {
    /// The bundle used to locate resource files.
    ///
    /// `Bundle.module` crashes on executable targets.  Defaults to
    /// `Bundle.main` (correct for the production .app).  Test suites
    /// inject `Bundle.module` before exercising catalog loading.
    static var catalogBundle: Bundle = .main

    static func loadBundled(bundle: Bundle = catalogBundle) throws -> AgentResourceCatalogDocument {
        guard let url = locateResource(named: "agent_resource_catalog", ext: "json", preferred: bundle) else {
            throw AgentResourceInstallError.catalogMissing
        }
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    /// Robustly locate a bundled resource. The SPM executable target ships
    /// resources in a nested `MyCoder_MyCoder.bundle` (or an injected test
    /// module bundle), NOT directly in `Bundle.main` — so searching only
    /// `.main` yielded "catalog missing" in the packaged .app (plan Раздел 13 п.9).
    /// We probe the preferred bundle, all loaded bundles, and any nested
    /// `.bundle` under their resource dirs, including a `Catalog/` subdirectory.
    static func locateResource(named name: String, ext: String, preferred: Bundle) -> URL? {
        var candidates: [Bundle] = [preferred, .main]
        candidates.append(contentsOf: Bundle.allBundles)
        candidates.append(contentsOf: Bundle.allFrameworks)

        // Also consider nested resource bundles inside each candidate's
        // Contents/Resources (SPM packages resources into <Target>_<Product>.bundle).
        for base in candidates {
            if let resURL = base.resourceURL,
               let entries = try? FileManager.default.contentsOfDirectory(at: resURL, includingPropertiesForKeys: nil) {
                for entry in entries where entry.pathExtension == "bundle" {
                    if let nested = Bundle(url: entry) { candidates.append(nested) }
                }
            }
        }

        var seen = Set<String>()
        for b in candidates {
            let key = b.bundleURL.path
            if seen.contains(key) { continue }
            seen.insert(key)
            if let url = b.url(forResource: name, withExtension: ext)
                ?? b.url(forResource: name, withExtension: ext, subdirectory: "Catalog") {
                return url
            }
        }
        return nil
    }

    static func load(from data: Data) throws -> AgentResourceCatalogDocument {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return try decoder.decode(AgentResourceCatalogDocument.self, from: data)
    }
}

enum AgentResourceLibraryLogic {
    static func filterSkills(_ skills: [CatalogSkillItem], query: String) -> [CatalogSkillItem] {
        filterCatalogItems(skills, query: query) { item in
            [item.name, item.description, item.category, item.id]
        }
    }

    static func filterMCPServers(_ servers: [CatalogMCPServerItem], query: String) -> [CatalogMCPServerItem] {
        filterCatalogItems(servers, query: query) { item in
            [item.name, item.description, item.category, item.id]
        }
    }

    static func isSkillInstalled(id: String, homeDirectory: URL) -> Bool {
        let paths = [
            MyCoderPaths.skillFile(id: id, homeDirectory: homeDirectory)
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func isMCPInstalled(id: String, homeDirectory: URL) -> Bool {
        let candidates = [
            MyCoderPaths.mcpConfigURL(homeDirectory: homeDirectory)
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let servers = (json["mcpServers"] as? [String: Any]) ?? json
            if servers[id] != nil {
                return true
            }
        }
        return false
    }

    private static func filterCatalogItems<T>(
        _ items: [T],
        query: String,
        fields: (T) -> [String]
    ) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            fields(item).contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }
}
