import Foundation

enum WorkspaceSortOrder: String, CaseIterable, Identifiable {
    case nameAsc = "Name A–Z"
    case nameDesc = "Name Z–A"
    case recentUse = "Recent use"
    case taskCount = "Task count"

    var id: String { rawValue }
}

enum WorkspaceViewMode: String {
    case list
    case grid
}

enum WorkspaceFilterPreset: String, CaseIterable {
    case all = "All"
    case hasSessions = "Has sessions"
    case empty = "Empty"
}

enum SidebarLayout {
    static let newTaskIcon = "plus.circle"
    static let sessionTaskIcon = "bubble.left"
    static let workspacesExpandIcon = "arrow.up.forward.square"
    static let workspacesFilterIcon = "line.3.horizontal.decrease"
    static let workspacesSearchIcon = "magnifyingglass"
    static let workspacesViewListIcon = "list.bullet"
    static let workspacesViewGridIcon = "square.grid.2x2"
}

enum SidebarWorkspaceLogic {

    static func filtered(_ workspaces: [Workspace], query: String) -> [Workspace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return workspaces }
        return workspaces.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
    
    static func filteredBySessionCount(_ workspaces: [Workspace], sessions: [ChatSession], preset: WorkspaceFilterPreset) -> [Workspace] {
        switch preset {
        case .all:
            return workspaces
        case .hasSessions:
            return workspaces.filter { sessionCount(for: $0, sessions: sessions) > 0 }
        case .empty:
            return workspaces.filter { sessionCount(for: $0, sessions: sessions) == 0 }
        }
    }

    static func sorted(_ workspaces: [Workspace], order: WorkspaceSortOrder, sessions: [ChatSession]) -> [Workspace] {
        switch order {
        case .nameAsc:
            return workspaces.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return workspaces.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .taskCount:
            return workspaces.sorted { sessionCount(for: $0, sessions: sessions) > sessionCount(for: $1, sessions: sessions) }
        case .recentUse:
            return workspaces.sorted {
                latestSessionDate(for: $0, sessions: sessions) > latestSessionDate(for: $1, sessions: sessions)
            }
        }
    }

    static func sessionCount(for workspace: Workspace, sessions: [ChatSession]) -> Int {
        sessions.filter { $0.belongs(to: workspace) }.count
    }

    static func latestSessionDate(for workspace: Workspace, sessions: [ChatSession]) -> Date {
        sessions
            .filter { $0.belongs(to: workspace) }
            .map(\.updatedAt)
            .max() ?? .distantPast
    }
}

#if canImport(AppKit)
import AppKit

enum UserProfileDisplay {
    static func displayName() -> String {
        let full = NSFullUserName()
        if !full.isEmpty { return full }
        let short = NSUserName()
        return short.isEmpty ? "MiMo User" : short
    }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
#else
enum UserProfileDisplay {
    static func displayName() -> String { "MiMo User" }
    static func initials(from name: String) -> String {
        String(name.prefix(2)).uppercased()
    }
}
#endif
