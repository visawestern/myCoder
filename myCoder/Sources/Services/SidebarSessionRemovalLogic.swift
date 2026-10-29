import Foundation

/// Keeps the in-memory sidebar caches in step with destructive row actions.
///
/// Deleting a chat removed it from `sessions` only. The sidebar tree is built
/// from its own per-project/project-less caches, so a deleted chat kept
/// hanging there; selecting it opened an empty chat because its history was
/// already gone from the database.
enum SidebarSessionRemovalLogic {
    static func removing(id: String, from sessions: [ChatSession]) -> [ChatSession] {
        sessions.filter { $0.id != id }
    }

    static func removing(
        id: String,
        from sessionsByProject: [String: [ChatSession]]
    ) -> [String: [ChatSession]] {
        sessionsByProject.mapValues { sessions in
            sessions.filter { $0.id != id }
        }
    }
}

/// Decides whether a sidebar row still points at a session that exists.
///
/// A row may survive in a cache after the chat was deleted elsewhere (API,
/// another path, an older build). Selecting such a row used to show a blank
/// chat; it must instead drop the stale row and say so.
enum SessionSelectionGuardLogic {
    enum Decision: Equatable {
        case proceed
        case removeStaleRow
    }

    static func decision(sessionIsInMemory: Bool, sessionExistsInStore: Bool) -> Decision {
        sessionIsInMemory || sessionExistsInStore ? .proceed : .removeStaleRow
    }
}
