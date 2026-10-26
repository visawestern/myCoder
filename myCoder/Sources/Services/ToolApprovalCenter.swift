import Foundation

/// Process-wide queue of tool calls waiting for the user's verdict.
///
/// Each direct-model turn registers its approvals before rendering the
/// Allow/Deny cards, then awaits them one by one. A verdict may arrive before
/// the loop reaches that call (the user can answer queued cards in any
/// order), so verdicts are buffered. Sessions are tracked independently:
/// stopping one chat denies only that chat's queued calls, while approvals
/// from other chats keep waiting. Registrations also carry the assistant
/// message ID, so switching back to a chat can reattach its still-pending
/// cards after the message history is reloaded from the database.
@MainActor
final class ToolApprovalCenter {
    static let shared = ToolApprovalCenter()

    private struct Registration {
        let approval: PendingToolApproval
        let sessionID: String
        let assistantID: String
    }

    private var waiters: [String: CheckedContinuation<Bool, Never>] = [:]
    private var bufferedVerdicts: [String: Bool] = [:]
    private var registrations: [String: Registration] = [:]

    private init() {}

    /// Registers an approval before its card becomes visible. Must happen
    /// before the user can resolve it, otherwise the verdict would be lost.
    func register(
        _ approval: PendingToolApproval,
        sessionID: String,
        assistantID: String
    ) {
        registrations[approval.id] = Registration(
            approval: approval,
            sessionID: sessionID,
            assistantID: assistantID
        )
    }

    /// Suspends until the user resolves this approval. If a verdict was
    /// already buffered, returns it immediately.
    func awaitVerdict(id: String) async -> Bool {
        if let buffered = bufferedVerdicts.removeValue(forKey: id) {
            registrations.removeValue(forKey: id)
            return buffered
        }
        return await withCheckedContinuation { continuation in
            if let buffered = bufferedVerdicts.removeValue(forKey: id) {
                registrations.removeValue(forKey: id)
                continuation.resume(returning: buffered)
            } else {
                waiters[id] = continuation
            }
        }
    }

    /// Delivers one verdict. A verdict for an approval that is not awaited
    /// yet is buffered; later `awaitVerdict(id:)` consumes it.
    func resolve(id: String, approved: Bool) {
        guard registrations[id] != nil || waiters[id] != nil else { return }
        registrations.removeValue(forKey: id)
        if let waiter = waiters.removeValue(forKey: id) {
            waiter.resume(returning: approved)
        } else {
            bufferedVerdicts[id] = approved
        }
    }

    /// Denies every queued approval belonging to one chat. Other chats keep
    /// their pending approvals untouched.
    func cancelPending(in sessionID: String) {
        let ids = registrations.compactMap { id, registration in
            registration.sessionID == sessionID ? id : nil
        }
        for id in ids {
            resolve(id: id, approved: false)
        }
    }

    func pendingApprovals(in sessionID: String) -> [PendingToolApproval] {
        registrations.values
            .filter { $0.sessionID == sessionID }
            .map(\.approval)
            .sorted { $0.createdAt < $1.createdAt }
    }

    func pendingApprovalsByAssistant(in sessionID: String) -> [String: [PendingToolApproval]] {
        Dictionary(grouping: registrations.values.filter { $0.sessionID == sessionID },
                   by: \.assistantID)
            .mapValues { registrations in
                registrations.map(\.approval).sorted { $0.createdAt < $1.createdAt }
            }
    }

    /// Pending approvals grouped by assistant message id, matched against the
    /// assistant messages that are actually loaded. Chat history reloads can
    /// happen while the turn's session id is still being swapped, so matching
    /// on the assistant message id keeps the cards attached to their message
    /// instead of silently dropping them.
    func pendingApprovals(matchingAssistantIDs assistantIDs: Set<String>) -> [String: [PendingToolApproval]] {
        Dictionary(grouping: registrations.values.filter { assistantIDs.contains($0.assistantID) },
                   by: \.assistantID)
            .mapValues { registrations in
                registrations.map(\.approval).sorted { $0.createdAt < $1.createdAt }
            }
    }

    func assistantID(for approvalID: String) -> String? {
        registrations[approvalID]?.assistantID
    }

    func pendingCount(in sessionID: String) -> Int {
        registrations.values.filter { $0.sessionID == sessionID }.count
    }

    func resetForTesting() {
        waiters.removeAll()
        bufferedVerdicts.removeAll()
        registrations.removeAll()
    }
}
