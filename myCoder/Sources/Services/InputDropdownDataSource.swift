import Foundation

/// Builds dropdown items for the in-input command palette from the active
/// registries/data, applies live filtering, and produces the text replacement
/// when an item is chosen (plan Раздел 6 Блок 1 п.9 / Блок 3). Pure/testable —
/// the SwiftUI view (InputCommandDropdownView) renders these results.
enum InputDropdownDataSource {

    /// Inputs the view provides from AppState (kept as plain values so this is
    /// unit-testable without UI/AppState).
    struct Context {
        var commands: [SlashCommand]
        var installedSkills: [String]     // skill ids/names
        var fileNames: [String]           // project files for @
        var sessionTitles: [String]       // sessions/tasks for #
        var recentCommandNames: [String]  // usage history for ranking
        var mcpServers: [String]          // configured MCP server names for $

        init(commands: [SlashCommand] = SlashCommandRegistry.builtInCommands,
             installedSkills: [String] = [],
             fileNames: [String] = [],
             sessionTitles: [String] = [],
             recentCommandNames: [String] = SlashCommandRegistry.usageHistory(),
             mcpServers: [String] = []) {
            self.commands = commands
            self.installedSkills = installedSkills
            self.fileNames = fileNames
            self.sessionTitles = sessionTitles
            self.recentCommandNames = recentCommandNames
            self.mcpServers = mcpServers
        }
    }

    /// Produce filtered, ordered items for a detected trigger.
    static func items(for trigger: TriggerContext, context: Context) -> [CommandDropdownItem] {
        let base: [CommandDropdownItem]
        switch trigger.source {
        case .commands:
            base = commandItems(context) + skillItems(context.installedSkills)
        case .files:
            base = fileItems(context.fileNames)
        case .sessions:
            base = sessionItems(context.sessionTitles)
        case .mcp:
            base = mcpItems(context.mcpServers)
        }
        let filtered = CommandDropdownFilter.filter(base, query: trigger.filter)
        return rankRecentFirst(filtered, recent: context.recentCommandNames)
    }

    private static func commandItems(_ ctx: Context) -> [CommandDropdownItem] {
        ctx.commands.map { cmd in
            CommandDropdownItem(id: "cmd:\(cmd.name)", title: cmd.displayName,
                                subtitle: cmd.description, category: "Commands",
                                icon: cmd.icon, kind: .command, actionKey: cmd.name)
        }
    }

    private static func skillItems(_ skills: [String]) -> [CommandDropdownItem] {
        skills.map { s in
            CommandDropdownItem(id: "skill:\(s)", title: s, subtitle: "Skill",
                                category: "Skills", icon: "wand.and.stars",
                                kind: .skill, actionKey: s)
        }
    }

    private static func fileItems(_ files: [String]) -> [CommandDropdownItem] {
        files.map { f in
            CommandDropdownItem(id: "file:\(f)", title: f, subtitle: "File",
                                category: "Files", icon: "doc", kind: .file, actionKey: f)
        }
    }

    private static func sessionItems(_ sessions: [String]) -> [CommandDropdownItem] {
        sessions.map { s in
            CommandDropdownItem(id: "session:\(s)", title: s, subtitle: "Session",
                                category: "Sessions", icon: "number", kind: .session, actionKey: s)
        }
    }

    private static func mcpItems(_ servers: [String]) -> [CommandDropdownItem] {
        servers.map { s in
            CommandDropdownItem(id: "mcp:\(s)", title: s, subtitle: "MCP server",
                                category: "MCP Servers", icon: "server.rack",
                                kind: .mcp, actionKey: s)
        }
    }

    /// Put recently-used commands first while keeping the rest in place.
    static func rankRecentFirst(_ items: [CommandDropdownItem], recent: [String]) -> [CommandDropdownItem] {
        guard !recent.isEmpty else { return items }
        let recentSet = recent
        let recentItems = recentSet.compactMap { name in items.first { $0.actionKey == name } }
        let rest = items.filter { item in !recentSet.contains(where: { $0 == item.actionKey }) }
        return recentItems + rest
    }

    /// Replace the trigger fragment in `text` with the chosen item, returning
    /// the new text and the caret position after insertion (plan Блок 2 п.17).
    static func applySelection(_ item: CommandDropdownItem,
                              trigger: TriggerContext,
                              text: String) -> (text: String, caret: Int) {
        let chars = Array(text)
        // Range to replace = from the trigger symbol to the current cursor
        // (trigger.triggerIndex .. triggerIndex + 1 + filter.count).
        let start = trigger.triggerIndex
        let end = min(chars.count, start + 1 + trigger.filter.count)
        let replacement: String
        switch item.kind {
        case .command:
            replacement = "/\(item.actionKey ?? item.title) "
        case .skill:
            replacement = "@skill:\(item.actionKey ?? item.title) "
        case .file:
            replacement = "@\(item.actionKey ?? item.title) "
        case .session:
            replacement = "#\(item.actionKey ?? item.title) "
        case .mcp:
            replacement = "$\(item.actionKey ?? item.title) "
        }
        let prefix = String(chars[0..<start])
        let suffix = end < chars.count ? String(chars[end...]) : ""
        let newText = prefix + replacement + suffix
        return (newText, (prefix + replacement).count)
    }

    /// Group items by category for sectioned rendering (plan Блок 2 п.16).
    static func grouped(_ items: [CommandDropdownItem]) -> [(category: String, items: [CommandDropdownItem])] {
        var order: [String] = []
        var map: [String: [CommandDropdownItem]] = [:]
        for item in items {
            if map[item.category] == nil { order.append(item.category) }
            map[item.category, default: []].append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}
