import Foundation

struct MCPServerEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let command: String?
    let isEnabled: Bool
    /// URL of an HTTP-transport MCP server (nil for stdio servers).
    let url: String?
    /// Launch arguments for a stdio-transport MCP server.
    let args: [String]

    init(id: String, name: String, command: String?, isEnabled: Bool,
         url: String? = nil, args: [String] = []) {
        self.id = id
        self.name = name
        self.command = command
        self.isEnabled = isEnabled
        self.url = url
        self.args = args
    }
}

struct SkillEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let source: String
}

struct PluginEntry: Identifiable, Equatable {
    let id: String
    let name: String
    var isEnabled: Bool
    let path: String

    private static let defaults = UserDefaults.standard
    private static let disabledKey = "disabledPlugins"

    static func togglePlugin(id: String) {
        let disabled = defaults.stringArray(forKey: disabledKey) ?? []
        defaults.set(PluginToggleLogic.toggledDisabledIDs(disabled, pluginID: id), forKey: disabledKey)
    }

    static func isPluginDisabled(id: String) -> Bool {
        let disabled = defaults.stringArray(forKey: disabledKey) ?? []
        return !PluginToggleLogic.isEnabled(pluginID: id, disabledIDs: disabled)
    }
}

enum AgentResourcesLoader {
    static func loadMCPServers(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [MCPServerEntry] {
        let candidates = [
            MyCoderPaths.mcpConfigURL(homeDirectory: homeDirectory)
        ]
        for url in candidates {
            if let servers = parseMCPConfig(at: url) {
                return servers
            }
        }
        return []
    }

    static func loadSkills(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SkillEntry] {
        let roots = [
            (MyCoderPaths.skillsDir(homeDirectory: homeDirectory), "myCoder")
        ]
        var results: [SkillEntry] = []
        for (root, source) in roots {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for folder in contents where folder.hasDirectoryPath {
                let skillFile = folder.appendingPathComponent("SKILL.md")
                guard FileManager.default.fileExists(atPath: skillFile.path) else { continue }
                results.append(SkillEntry(
                    id: folder.lastPathComponent,
                    name: folder.lastPathComponent,
                    path: skillFile.path,
                    source: source
                ))
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func loadPlugins(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [PluginEntry] {
        let root = MyCoderPaths.pluginsDir(homeDirectory: homeDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { folder -> PluginEntry? in
            guard folder.hasDirectoryPath else { return nil }
            let manifest = folder.appendingPathComponent("plugin.json")
            let name: String
            if let data = try? Data(contentsOf: manifest),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let manifestName = json["name"] as? String {
                name = manifestName
            } else {
                name = folder.lastPathComponent
            }
            let manifestExists = (try? manifest.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            let id = folder.lastPathComponent
            let disabledByUser = PluginEntry.isPluginDisabled(id: id)
            let enabled = manifestExists && !disabledByUser
            return PluginEntry(
                id: id,
                name: name,
                isEnabled: enabled,
                path: folder.path
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func loadCommands(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CommandEntry] {
        CommandFileManager.load(homeDirectory: homeDirectory)
    }

    static func filterSkills(_ skills: [SkillEntry], query: String) -> [SkillEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return skills }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.source.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static func filterEntries<T>(_ entries: [T], query: String, name: (T) -> String) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { name($0).localizedCaseInsensitiveContains(trimmed) }
    }

    private static func parseMCPConfig(at url: URL) -> [MCPServerEntry]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let serversObject = (json["mcpServers"] as? [String: Any]) ?? json
        guard !serversObject.isEmpty else { return [] }

        return serversObject.compactMap { key, value -> MCPServerEntry? in
            guard let config = value as? [String: Any] else { return nil }
            let url = config["url"] as? String
            let command = (config["command"] as? String) ?? url
            let args = config["args"] as? [String] ?? []
            let disabled = config["disabled"] as? Bool ?? false
            return MCPServerEntry(
                id: key,
                name: key,
                command: command,
                isEnabled: !disabled,
                url: url,
                args: args
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum PlusMenuCapabilityLogic {
    static func visibleItems(_ all: [PlusMenuItem], canUseTools: Bool) -> [PlusMenuItem] {
        guard canUseTools else {
            return all.filter { $0 == .addAttachment || $0 == .addPhoto }
        }
        return all
    }
}
