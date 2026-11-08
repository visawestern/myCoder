import Foundation

/// The visible state of a model-switch compaction.
///
/// User directive 2026-11-08: switching to a model with a smaller context
/// window compacts the chat before it continues — and the user keeps control:
/// the compaction can be stopped, rolled back, or replaced by another model
/// with a larger window. This model carries exactly those states; the chat
/// panel renders them and the send path acts on them.
struct ModelSwitchCompactionNotice: Equatable, Sendable {

    enum Phase: String, Equatable, Sendable {
        /// The decision is made; the compaction has not started yet.
        case pending
        /// The summary is being produced right now.
        case running
        /// The summary is in the feed and the model history starts from it.
        case compacted
        /// The user stopped the compaction; the history is untouched.
        case cancelled
        /// The compaction failed; the history is untouched.
        case failed
        /// The compaction was rolled back; the history is whole again.
        case rolledBack
    }

    let previousModel: String
    let newModel: String
    /// Tokens the chat occupied when the model was switched.
    let usedTokens: Int
    /// Context window of the newly selected model.
    let limitTokens: Int
    var phase: Phase
    /// Models that can hold the current context without compaction. The
    /// provider travels with the model: the bigger window may live in another
    /// provider, and choosing it switches both.
    var alternatives: [ModelSwitchCompactionLogic.Candidate]
    /// The appended summary — the rollback removes it.
    var summaryMessageID: String?
    /// The appended "context compacted" note — the rollback removes it too.
    var noticeMessageID: String?
    /// Why the compaction failed, when it did.
    var error: String?
    /// Chat the notice belongs to. The rollback removes the messages from
    /// THIS conversation, so a notice must never touch another chat's feed.
    var sessionID: String?
    /// Whether running the compaction again can help. A provider that keeps
    /// the history on the server will fail the same way every time.
    var retryable: Bool = true

    /// The compaction can be stopped while it is pending or running.
    var canStop: Bool { phase == .pending || phase == .running }

    /// A finished compaction can be rolled back.
    var canRollback: Bool { phase == .compacted && summaryMessageID != nil }

    /// A stopped, failed or rolled-back compaction can be started again.
    var canRetry: Bool {
        retryable && (phase == .cancelled || phase == .failed || phase == .rolledBack)
    }
}
