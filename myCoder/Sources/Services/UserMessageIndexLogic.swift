import Foundation

/// Builds and maintains the in-memory index of every user message in a chat.
///
/// Input: lightweight database rows (`UserMessageIndexRecord`) and/or live
/// `Message` values. Output: an ordered, sequentially numbered list of
/// `UserMessageIndexEntry` covering the WHOLE session.
///
/// Dependencies: only `UserMessageNavigatorLogic` for preview normalisation.
/// No UI, no database, no SwiftUI — every function is pure and movable.
enum UserMessageIndexLogic {

    /// How many characters the database stores per user message. It must stay
    /// comfortably above the 100-character preview so whitespace collapsing
    /// still has something to work with, while never loading whole pastes.
    static let storedPrefixLength = 300

    /// Convert database rows (already ordered oldest → newest) into numbered
    /// entries. Rows whose visible preview is empty are skipped, exactly like
    /// the navigator's old filter, so numbering matches what the user sees.
    ///
    /// - Parameter records: lightweight rows in display order.
    /// - Returns: entries numbered 1…n.
    static func entries(from records: [UserMessageIndexRecord]) -> [UserMessageIndexEntry] {
        var result: [UserMessageIndexEntry] = []
        result.reserveCapacity(records.count)
        for record in records {
            let preview = preview(for: record)
            guard !preview.isEmpty else { continue }
            result.append(UserMessageIndexEntry(
                id: record.id,
                ordinal: result.count + 1,
                preview: preview
            ))
        }
        return result
    }

    /// Build an index from messages already in memory. Used for a brand-new
    /// chat that has not reached the database yet, and as a safety net when the
    /// stored index is empty (server-only history).
    ///
    /// - Parameter messages: loaded messages in display order.
    /// - Returns: entries numbered 1…n.
    static func entries(fromMessages messages: [Message]) -> [UserMessageIndexEntry] {
        merging(messages: messages, into: [])
    }

    /// Merge live loaded messages into a stored index.
    ///
    /// Responsibilities:
    /// - refresh previews for entries that are loaded (content may be newer
    ///   than the database row);
    /// - insert messages the database does not know yet into their correct
    ///   gap, so an older server page or a live tail keeps session order;
    /// - renumber the result 1…n.
    ///
    /// - Parameters:
    ///   - messages: loaded messages in display order (may be a middle window).
    ///   - entries: current session index.
    /// - Returns: merged, renumbered entries.
    static func merging(
        messages: [Message],
        into entries: [UserMessageIndexEntry]
    ) -> [UserMessageIndexEntry] {
        var previewByID: [String: String] = [:]
        var loadedUserIDs: [String] = []
        for message in messages where message.role == .user {
            let preview = UserMessageNavigatorLogic.preview(for: message)
            guard !preview.isEmpty else { continue }
            previewByID[message.id] = preview
            loadedUserIDs.append(message.id)
        }

        let knownIDs = Set(entries.map(\.id))
        // Missing ids form runs between two known neighbours. A run before a
        // known id is inserted there; a trailing run is appended.
        var insertionsBefore: [String: [String]] = [:]
        var trailing: [String] = []
        var pending: [String] = []
        for id in loadedUserIDs {
            if knownIDs.contains(id) {
                if !pending.isEmpty {
                    insertionsBefore[id] = pending
                    pending = []
                }
            } else {
                pending.append(id)
            }
        }
        trailing = pending

        var result: [UserMessageIndexEntry] = []
        result.reserveCapacity(entries.count + trailing.count)
        for entry in entries {
            if let inserted = insertionsBefore[entry.id] {
                append(inserted, previewByID: previewByID, to: &result)
            }
            result.append(UserMessageIndexEntry(
                id: entry.id,
                ordinal: result.count + 1,
                preview: previewByID[entry.id] ?? entry.preview
            ))
        }
        append(trailing, previewByID: previewByID, to: &result)
        return result
    }

    /// Add one live message. Idempotent: re-saving the same user message only
    /// refreshes its preview. Assistant/system rows are ignored.
    ///
    /// - Parameters:
    ///   - message: the message that was just appended or updated.
    ///   - entries: current session index.
    /// - Returns: updated, renumbered entries.
    static func appending(
        _ message: Message,
        to entries: [UserMessageIndexEntry]
    ) -> [UserMessageIndexEntry] {
        merging(messages: [message], into: entries)
    }

    /// Remove a deleted message and renumber the remaining entries.
    ///
    /// - Parameters:
    ///   - id: message id to drop (compaction rollback, manual delete).
    ///   - entries: current session index.
    /// - Returns: renumbered entries without `id`.
    static func removing(
        id: String,
        from entries: [UserMessageIndexEntry]
    ) -> [UserMessageIndexEntry] {
        entries
            .filter { $0.id != id }
            .enumerated()
            .map { index, entry in
                UserMessageIndexEntry(
                    id: entry.id,
                    ordinal: index + 1,
                    preview: entry.preview
                )
            }
    }

    /// Short preview for a stored row. The stored prefix is already truncated
    /// in SQL; `isTruncated` keeps the ellipsis when the original text is
    /// longer than the prefix.
    ///
    /// - Parameter record: lightweight database row.
    /// - Returns: normalised preview, at most 100 characters plus ellipsis.
    static func preview(for record: UserMessageIndexRecord) -> String {
        let scan = UserMessageNavigatorLogic.normalizedPrefix(
            record.contentPrefix,
            limit: UserMessageNavigatorLogic.previewCharacterLimit
        )
        let text = scan.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "" }
        let hasMore = scan.hasMore || record.isTruncated
        return hasMore ? text + "…" : text
    }

    /// Append a run of already ordered ids, using their live previews.
    private static func append(
        _ ids: [String],
        previewByID: [String: String],
        to result: inout [UserMessageIndexEntry]
    ) {
        for id in ids {
            result.append(UserMessageIndexEntry(
                id: id,
                ordinal: result.count + 1,
                preview: previewByID[id] ?? ""
            ))
        }
    }
}
