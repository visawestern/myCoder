import Foundation

/// What must happen when the user switches to a model whose context window is
/// smaller than the chat's current context.
///
/// User directive 2026-11-08: the chat must be compacted before it continues
/// with the new model — and the user keeps control: the compaction can be
/// stopped, rolled back, or replaced by choosing another model with a larger
/// window. This file holds the decision only; the UI and the send path apply
/// it.
enum ModelSwitchCompactionLogic {

    struct Decision: Equatable, Sendable {
        /// True when the current context does not fit into the new window.
        let required: Bool
        /// Tokens the chat currently occupies (model-bound history).
        let usedTokens: Int
        /// Context window of the newly selected model.
        let limitTokens: Int

        /// How many tokens do not fit. Zero when everything fits — and zero
        /// when the window is unknown: there is nothing to overflow.
        var overflowTokens: Int {
            limitTokens > 0 ? max(0, usedTokens - limitTokens) : 0
        }
    }

    /// A model and the context window it offers, together with the provider
    /// it lives in.
    ///
    /// The provider is part of the answer: the escape hatch after a model
    /// switch often lives in another provider entirely — a live run showed an
    /// empty list because only the current provider was searched.
    struct Candidate: Equatable, Sendable {
        let id: String
        let window: Int
        let providerID: String
        let providerName: String

        /// Stable identity of the choice: the same model id can exist in
        /// several providers, so the model id alone is not enough.
        var key: String { "\(providerID)::\(id)" }
    }

    /// One provider with the models it offers and their context windows.
    struct ProviderModels: Equatable, Sendable {
        struct Model: Equatable, Sendable {
            let id: String
            let window: Int
        }
        let providerID: String
        let providerName: String
        let models: [Model]
    }

    /// Flatten provider catalogs into the candidate list the decision uses.
    static func candidates(from providers: [ProviderModels]) -> [Candidate] {
        providers.flatMap { provider in
            provider.models.map { model in
                Candidate(
                    id: model.id,
                    window: model.window,
                    providerID: provider.providerID,
                    providerName: provider.providerName
                )
            }
        }
    }

    /// The context fits when it is not larger than the window. An unknown
    /// window (0) never forces a compaction: the host must not destroy the
    /// user's history because a provider reported no metadata.
    static func decision(usedTokens: Int, limitTokens: Int) -> Decision {
        let required = limitTokens > 0 && usedTokens > limitTokens
        return Decision(required: required, usedTokens: usedTokens, limitTokens: limitTokens)
    }

    /// Models that can hold the current context without compaction, biggest
    /// window first. These are the escape hatch: switch to one of them and the
    /// chat continues untouched. The list spans every provider — the bigger
    /// window is often not in the current one.
    static func modelsThatFit(usedTokens: Int, candidates: [Candidate]) -> [Candidate] {
        candidates
            .filter { $0.window > 0 && $0.window >= usedTokens }
            .sorted { lhs, rhs in
                if lhs.window != rhs.window { return lhs.window > rhs.window }
                if lhs.providerName != rhs.providerName { return lhs.providerName < rhs.providerName }
                return lhs.id < rhs.id
            }
    }

    /// How many alternatives the banner offers. The list of models that hold
    /// the context can run into a hundred entries — a menu with a hundred
    /// items is not a choice, so the biggest windows win the places.
    static let maxAlternatives = 12

    /// Whether a switch into `limitTokens` forces the chat to be compacted.
    ///
    /// An empty `previousModel` means there was no model to switch FROM (the
    /// app restored its selection at launch) — that is not a switch, so the
    /// chat must not be compacted behind the user's back.
    static func requiresCompaction(previousModel: String,
                                   usedTokens: Int,
                                   limitTokens: Int) -> Bool {
        guard !previousModel.isEmpty else { return false }
        return decision(usedTokens: usedTokens, limitTokens: limitTokens).required
    }

    /// The notice for a model switch — or nil when the chat fits into the new
    /// window and nothing has to happen.
    static func notice(previousModel: String,
                       newModel: String,
                       usedTokens: Int,
                       limitTokens: Int,
                       candidates: [Candidate],
                       sessionID: String?) -> ModelSwitchCompactionNotice? {
        guard requiresCompaction(
            previousModel: previousModel,
            usedTokens: usedTokens,
            limitTokens: limitTokens
        ) else { return nil }
        return ModelSwitchCompactionNotice(
            previousModel: previousModel,
            newModel: newModel,
            usedTokens: usedTokens,
            limitTokens: limitTokens,
            phase: .pending,
            alternatives: Array(
                modelsThatFit(usedTokens: usedTokens, candidates: candidates)
                    .prefix(maxAlternatives)
            ),
            summaryMessageID: nil,
            noticeMessageID: nil,
            error: nil,
            sessionID: sessionID
        )
    }

    /// Which messages a rollback removes: the appended note and the appended
    /// summary. Nothing else — the original turns were never dropped from the
    /// feed, only from the model's view.
    static func rollbackTargets(summaryMessageID: String?, noticeMessageID: String?) -> [String] {
        [noticeMessageID, summaryMessageID]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    /// Phase of the notice after a compaction attempt.
    static func phase(for outcome: ConversationCompactionOutcome) -> ModelSwitchCompactionNotice.Phase {
        switch outcome {
        case .compacted: return .compacted
        case .cancelled: return .cancelled
        case .failed, .unsupported, .nothingToCompact: return .failed
        }
    }

    /// The chat must not continue while its own compaction is still running:
    /// the turn would be built from a history that is about to be replaced.
    ///
    /// A stopped or failed compaction does NOT block the send — the user
    /// explicitly took over, and the banner keeps the warning visible.
    static func blocksSend(phase: ModelSwitchCompactionNotice.Phase) -> Bool {
        phase == .pending || phase == .running
    }
}
