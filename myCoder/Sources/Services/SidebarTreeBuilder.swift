import Foundation

/// A project row in the sidebar tree. Its chats are the children.
struct SidebarProjectNode: Identifiable {
    let workspace: Workspace
    let sessions: [ChatSession]
    let isPinned: Bool

    var id: String { workspace.id }
    var name: String { workspace.name }

    /// Namespaced pin ID, so a project and a chat can never share a pin slot.
    var pinID: String { SidebarPinID.project(workspace.id) }
}

/// A chat without a project. It is rendered as its own top-level row (like a
/// project row, but with a chat icon) so it never mixes into a project's
/// children.
struct SidebarProjectlessChatNode: Identifiable {
    let id: String
    let title: String
    let session: ChatSession
    let isPinned: Bool

    var pinID: String { SidebarPinID.chat(id) }
}

/// Namespaced IDs for pinned sidebar rows.
enum SidebarPinID {
    static func project(_ id: String) -> String { "project:\(id)" }
    static func chat(_ id: String) -> String { "chat:\(id)" }
}

/// One top-level row of the sidebar tree.
enum SidebarTreeItem: Identifiable {
    case project(SidebarProjectNode)
    case projectlessChat(SidebarProjectlessChatNode)

    var id: String {
        switch self {
        case .project(let node): return "project-\(node.id)"
        case .projectlessChat(let node): return "chat-\(node.id)"
        }
    }

    var isPinned: Bool {
        switch self {
        case .project(let node): return node.isPinned
        case .projectlessChat(let node): return node.isPinned
        }
    }

    var title: String {
        switch self {
        case .project(let node): return node.name
        case .projectlessChat(let node): return node.title
        }
    }
}

/// Builds the sidebar tree in one pass.
///
/// Rules:
/// - every chat belongs to exactly one row (a project child or a project-less
///   top-level row), never both and never twice;
/// - project children are sorted by recent activity, so a chat only moves up
///   when something actually changed in it;
/// - pinned rows float to the top while keeping their relative order.
enum SidebarTreeBuilder {
    static func build(
        workspaces: [Workspace],
        sessionsByWorkspaceID: [String: [ChatSession]],
        projectlessSessions: [ChatSession],
        pinnedIDs: Set<String> = []
    ) -> [SidebarTreeItem] {
        var childIDs = Set<String>()
        var projectItems: [SidebarTreeItem] = []

        for workspace in workspaces {
            let sessions = (sessionsByWorkspaceID[workspace.id] ?? [])
                .sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                    return lhs.id < rhs.id
                }
            childIDs.formUnion(sessions.map(\.id))
            projectItems.append(.project(SidebarProjectNode(
                workspace: workspace,
                sessions: sessions,
                isPinned: pinnedIDs.contains(SidebarPinID.project(workspace.id))
            )))
        }

        // A chat that already belongs to a project must not appear again as a
        // project-less row.
        let standalone = projectlessSessions
            .filter { !childIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id < rhs.id
            }
            .map { session in
                SidebarTreeItem.projectlessChat(SidebarProjectlessChatNode(
                    id: session.id,
                    title: session.title,
                    session: session,
                    isPinned: pinnedIDs.contains(SidebarPinID.chat(session.id))
                ))
            }

        let all = projectItems + standalone
        let pinned = all.filter(\.isPinned)
        let unpinned = all.filter { !$0.isPinned }
        return pinned + unpinned
    }
}

/// Persistence for pinned sidebar rows.
enum SidebarPinStore {
    static let defaultsKey = MyCoderDefaults.key("pinnedSidebarItems")

    static func load(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    static func save(_ ids: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(ids).sorted(), forKey: defaultsKey)
    }
}
