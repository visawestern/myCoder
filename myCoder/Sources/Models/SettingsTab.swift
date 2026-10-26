import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case codePreview = "Code preview"
    case modelSettings = "Model settings"
    case providers = "Providers"
    case skills = "Skills"
    case mcpServers = "MCP Servers"
    case plugins = "Plugins"
    case commands = "Commands"
    case indexing = "Indexing"
    case storage = "Storage"
    case usage = "Usage"
    
    var id: String { rawValue }

    /// Tabs shown in the Settings sidebar. `.modelSettings` is merged into
    /// `.providers` (plan Раздел 1 Блок 3) — the case is kept for back-compat
    /// (deep links / stored last tab) but hidden from the visible list, which
    /// renders a single "Providers" tab.
    static var visibleCases: [SettingsTab] {
        allCases.filter { $0 != .modelSettings }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .codePreview: return "chevron.left.forwardslash.chevron.right"
        case .modelSettings: return "cpu"
        case .providers: return "server.rack"
        case .skills: return "wand.and.stars"
        case .mcpServers: return "server.rack"
        case .plugins: return "puzzlepiece"
        case .commands: return "terminal"
        case .indexing: return "checkmark.circle"
        case .storage: return "externaldrive"
        case .usage: return "chart.bar"
        }
    }
}
