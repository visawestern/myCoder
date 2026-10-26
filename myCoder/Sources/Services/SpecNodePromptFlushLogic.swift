import Foundation

/// Guards the one-shot coder prompt: it may be sent only after the target chat
/// is selected, its history is fully applied, and no request is in flight.
enum SpecNodePromptFlushLogic {
    /// True when the pending prompt's chat is selected but its history is not
    /// loaded yet. The view uses this to start the missing load itself when a
    /// session switch did not trigger one (e.g. the store still pointed at a
    /// previous spec-node chat).
    static func needsHistoryLoad(pendingSessionID: String?,
                                 selectedSessionID: String?,
                                 loadedSessionID: String?,
                                 isLoadingMessages: Bool) -> Bool {
        guard let pendingSessionID,
              pendingSessionID == selectedSessionID else { return false }
        return loadedSessionID != pendingSessionID && !isLoadingMessages
    }

    static func shouldFlush(pendingSessionID: String?,
                            selectedSessionID: String?,
                            currentSessionID: String?,
                            loadedSessionID: String?,
                            isLoadingMessages: Bool,
                            isBusy: Bool) -> Bool {
        guard let pendingSessionID else { return false }
        return pendingSessionID == selectedSessionID
            && pendingSessionID == currentSessionID
            && pendingSessionID == loadedSessionID
            && !isLoadingMessages
            && !isBusy
    }
}
