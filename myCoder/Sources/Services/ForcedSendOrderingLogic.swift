import Foundation

/// The force-send sequence for one queued message.
///
/// The user bubble is shown BEFORE the interrupted turn is awaited. Waiting
/// first left the feed unchanged for as long as the old turn kept streaming;
/// the send looked lost, users re-sent it, and the database ended up with two
/// user messages for one forced turn.
@MainActor
enum ForcedSendOrderingLogic {

    /// Runs the sequence in the only correct order and returns the bubble id.
    /// Every step is injected so the order is testable without a live view.
    @discardableResult
    static func run(showUserMessage: @MainActor () async -> String?,
                    waitForPreviousTurn: @MainActor () async -> Void,
                    send: @MainActor (String?) async -> Void) async -> String? {
        let bubbleID = await showUserMessage()
        await waitForPreviousTurn()
        guard !Task.isCancelled else { return bubbleID }
        await send(bubbleID)
        return bubbleID
    }
}
