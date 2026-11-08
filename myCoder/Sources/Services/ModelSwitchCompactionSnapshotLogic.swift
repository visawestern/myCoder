import Foundation

/// Builds the `modelSwitchCompaction` block of the `/api/state` snapshot.
///
/// The compaction that follows a model switch is a visible, controllable
/// action: the user must be able to see that it is running, stop it, roll it
/// back or pick a larger model. Over HTTP the same facts have to be visible —
/// otherwise "is the chat compacting right now?" can only be answered by
/// looking at the screen.
enum ModelSwitchCompactionSnapshotLogic {

    static func block(_ notice: ModelSwitchCompactionNotice?) -> [String: Any] {
        guard let notice else {
            return ["active": false]
        }
        return [
            "active": true,
            "phase": notice.phase.rawValue,
            "previousModel": notice.previousModel,
            "newModel": notice.newModel,
            "usedTokens": notice.usedTokens,
            "limitTokens": notice.limitTokens,
            "overflowTokens": max(0, notice.usedTokens - notice.limitTokens),
            "alternatives": notice.alternatives.map { candidate in
                [
                    "providerID": candidate.providerID,
                    "providerName": candidate.providerName,
                    "modelID": candidate.id,
                    "window": candidate.window
                ]
            },
            "canStop": notice.canStop,
            "canRollback": notice.canRollback,
            "canRetry": notice.canRetry,
            "error": notice.error ?? NSNull(),
            "sessionID": notice.sessionID ?? NSNull()
        ]
    }
}
