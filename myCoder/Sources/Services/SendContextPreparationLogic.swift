import Foundation

/// Why context was (or was not) attached to a turn. The UI uses this to stay
/// quiet when there was simply nothing to collect instead of showing a failure
/// banner on every message.
enum SendContextStatus: Equatable, Sendable {
    /// The feature is off, or the message is blank.
    case disabled
    /// The chat has no project, so there is no project context to collect.
    /// This is a normal state, never a failure.
    case projectless
    /// The compiler ran but nothing matched the request. The model receives
    /// the raw message; no evidence is invented and no error is claimed.
    case noEvidence
    /// A pack with citations/memories/ledger state was assembled.
    case compiled
    /// The project has an index but it could not be read, or it is empty.
    case failed
}

/// What the send path hands to the provider after context compilation.
struct SendContextPreparation: Equatable, Sendable {
    /// Text sent to the model. The visible chat bubble always keeps the raw
    /// user message, so this may differ from what the user typed.
    let modelText: String
    /// The pack that was assembled, when compilation ran.
    let pack: CompiledContextPack?
    /// Visible reason when the context could not be assembled. Sending still
    /// proceeds — a compiler failure must never block the user.
    let warning: String?
    /// Why the pack is (not) here. `noEvidence` and `projectless` are normal,
    /// so neither produces a warning banner.
    let status: SendContextStatus
}

enum SendContextPreparationLogic {

    static func prepare(message: String,
                        records: [FileIndexRecord],
                        projectPath: String,
                        isEnabled: Bool,
                        memories: [ProjectMemoryChunk] = [],
                        ledger: TaskLedger? = nil,
                        extraWarning: String? = nil,
                        localPlan: LocalQueryPlanResult? = nil,
                        board preparedBoard: ContextBoard? = nil,
                        budgetTokens: Int = TurnContextCompiler.defaultBudgetTokens) -> SendContextPreparation {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty else {
            return SendContextPreparation(modelText: message, pack: nil,
                                          warning: extraWarning, status: .disabled)
        }
        // A chat without a project has nothing to collect from. Warning here
        // fired on every message in "Без проекта" even though nothing was
        // wrong — the send is complete without project evidence.
        guard !projectPath.isEmpty else {
            return SendContextPreparation(modelText: message, pack: nil,
                                          warning: combinedWarning(nil, extraWarning),
                                          status: .projectless)
        }
        guard !records.isEmpty || !memories.isEmpty || ledger != nil else {
            return SendContextPreparation(
                modelText: message,
                pack: nil,
                warning: combinedWarning(L.t(AppLocalizationKey.locContextCompilationFailed), extraWarning),
                status: .failed
            )
        }

        let board = preparedBoard ?? ContextBoardBuilder.build(projectPath: projectPath, records: records)
        let pack = TurnContextCompiler.compile(
            message: trimmed,
            board: board,
            projectRoot: projectPath,
            memories: memories,
            ledger: ledger,
            budgetTokens: budgetTokens,
            localPlan: localPlan
        )
        guard !pack.citations.isEmpty || !pack.memoryIDs.isEmpty || pack.ledgerSummary != nil else {
            // The compiler ran and honestly found no matching evidence. The
            // raw message goes out; this is not a compilation failure, so no
            // error banner is shown.
            return SendContextPreparation(
                modelText: message,
                pack: nil,
                warning: combinedWarning(nil, extraWarning),
                status: .noEvidence
            )
        }
        return SendContextPreparation(
            modelText: pack.text,
            pack: pack,
            warning: combinedWarning(nil, extraWarning),
            status: .compiled
        )
    }

    private static func combinedWarning(_ first: String?, _ second: String?) -> String? {
        let parts = [first, second].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// True when the model should receive the ledger instead of the raw prior
    /// turns. The ledger itself already lives in the pack text.
    static func replacesRawHistory(_ preparation: SendContextPreparation,
                                   priorTurnCount: Int) -> Bool {
        TaskLedgerPolicy.replacesRawHistory(
            summary: preparation.pack?.ledgerSummary,
            priorTurnCount: priorTurnCount
        )
    }

    /// The chat part that carries the pack behind the "Контекст" button.
    /// Empty when no pack was built, so a plain message stays a plain message.
    static func contextParts(_ preparation: SendContextPreparation) -> [MessagePartContent] {
        guard let pack = preparation.pack, !pack.text.isEmpty else { return [] }
        return [.compiledContext(pack.text)]
    }

    /// Same as `prepare`, off the main thread: ranking and reading files are
    /// synchronous disk work and must not freeze the composer. The caller owns
    /// the "compiling" state so the UI can show it.
    static func prepareAsync(message: String,
                            records: [FileIndexRecord],
                            projectPath: String,
                            isEnabled: Bool,
                            memories: [ProjectMemoryChunk] = [],
                            ledger: TaskLedger? = nil,
                            extraWarning: String? = nil,
                            localPlan: LocalQueryPlanResult? = nil,
                            board: ContextBoard? = nil,
                            budgetTokens: Int = TurnContextCompiler.defaultBudgetTokens) async -> SendContextPreparation {
        await Task.detached(priority: .userInitiated) {
            prepare(
                message: message,
                records: records,
                projectPath: projectPath,
                isEnabled: isEnabled,
                memories: memories,
                ledger: ledger,
                extraWarning: extraWarning,
                localPlan: localPlan,
                board: board,
                budgetTokens: budgetTokens
            )
        }.value
    }
}
