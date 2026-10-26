import Foundation

enum GitRefreshScheduler {
    static func resolvedSessionID(explicit: String?, selected: String?) -> String? {
        if let explicit, !explicit.isEmpty { return explicit }
        if let selected, !selected.isEmpty { return selected }
        return nil
    }
}
