import Foundation

struct ChatSession: Identifiable {
    /// Reserved project key for standalone chats — conversations that do not
    /// belong to any workspace (user directive 2026-09-08: a chat started
    /// without a project must persist and stay visible in the sidebar).
    /// Stored in the global database under this `project_id`; the synthetic
    /// "Chats" sidebar group lists them.
    static let standaloneProjectKey = "standalone"

    let id: String
    var title: String
    var messages: [Message]
    var isActive: Bool
    let createdAt: Date
    var updatedAt: Date
    var directory: String
    var branch: String?
    var gitSummary: MimoSessionSummary?
    /// Current session goal set via /goal, shown in the TopBar (plan Раздел 5 Блок 1 п.8).
    var sessionGoal: String?
    /// Model the chat used last, restored when the chat is reopened.
    var modelID: String?
    /// Provider the chat used last, restored when the chat is reopened.
    var providerID: String?
    /// Set for sub-agent chats: the id of the chat that spawned this one.
    /// Sub-agent chats are listed in the right panel, never in the sidebar.
    var parentSessionID: String?
    /// Sub-agent lifecycle: "running" | "done" | "failed". nil for normal chats.
    var subagentStatus: String?

    init(
        id: String = UUID().uuidString,
        title: String = "New Chat",
        messages: [Message] = [],
        isActive: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        directory: String = "",
        branch: String? = nil,
        gitSummary: MimoSessionSummary? = nil,
        sessionGoal: String? = nil,
        modelID: String? = nil,
        providerID: String? = nil,
        parentSessionID: String? = nil,
        subagentStatus: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.directory = directory
        self.branch = branch
        self.gitSummary = gitSummary
        self.sessionGoal = sessionGoal
        self.modelID = modelID
        self.providerID = providerID
        self.parentSessionID = parentSessionID
        self.subagentStatus = subagentStatus
    }
    
    var durationLabel: String {
        Self.durationLabel(since: updatedAt)
    }
    
    func belongs(to workspace: Workspace) -> Bool {
        Self.normalizedPath(directory) == Self.normalizedPath(workspace.path)
    }
    
    static func durationLabel(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }

        let days = hours / 24
        return "\(days)d"
    }
    
    static func normalizedPath(_ path: String) -> String {
        // `standardizingPath` alone is NOT idempotent for the well-known
        // /var -> /private/var (and /tmp) symlinks: whether it resolves them
        // depends on the path already existing on disk, so the same project
        // reached as "/var/…" vs "/private/var/…" could produce two different
        // pool keys (Round 7 flaky pool-eviction bug). Resolve symlinks
        // explicitly so the result is stable and idempotent regardless of the
        // spelling the caller used.
        let standardized = (path as NSString).standardizingPath
        return (standardized as NSString).resolvingSymlinksInPath
    }
}
