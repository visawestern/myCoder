import Foundation

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
}

enum SendContextPreparationLogic {

    static func prepare(message: String,
                        records: [FileIndexRecord],
                        projectPath: String,
                        isEnabled: Bool,
                        memories: [ProjectMemoryChunk] = [],
                        ledger: TaskLedger? = nil,
                        extraWarning: String? = nil,
                        budgetTokens: Int = TurnContextCompiler.defaultBudgetTokens) -> SendContextPreparation {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty else {
            return SendContextPreparation(modelText: message, pack: nil, warning: extraWarning)
        }
        guard !projectPath.isEmpty, !records.isEmpty || !memories.isEmpty || ledger != nil else {
            return SendContextPreparation(
                modelText: message,
                pack: nil,
                warning: combinedWarning(L.t(AppLocalizationKey.locContextCompilationFailed), extraWarning)
            )
        }

        let board = ContextBoardBuilder.build(projectPath: projectPath, records: records)
        let pack = TurnContextCompiler.compile(
            message: trimmed,
            board: board,
            projectRoot: projectPath,
            memories: memories,
            ledger: ledger,
            budgetTokens: budgetTokens
        )
        guard !pack.citations.isEmpty || !pack.memoryIDs.isEmpty || pack.ledgerSummary != nil else {
            // No evidence means no context: send the raw message and say why,
            // instead of pretending a pack was built.
            return SendContextPreparation(
                modelText: message,
                pack: pack,
                warning: combinedWarning(L.t(AppLocalizationKey.locContextCompilationFailed), extraWarning)
            )
        }
        return SendContextPreparation(
            modelText: pack.text,
            pack: pack,
            warning: combinedWarning(nil, extraWarning)
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
                budgetTokens: budgetTokens
            )
        }.value
    }
}
