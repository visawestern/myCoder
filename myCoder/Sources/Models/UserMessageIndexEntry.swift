import Foundation

/// One user message of a whole chat session.
///
/// The navigator must list every question the user ever asked, not only the
/// page that is currently materialised in the feed. The index is built from a
/// lightweight database query and kept in memory by `MessageStore`.
///
/// - `id`: stable message id used to scroll and to merge live updates.
/// - `ordinal`: 1-based number across the WHOLE session (never resets when an
///   older page is prepended).
/// - `preview`: already-normalised short text for the hover tooltip.
struct UserMessageIndexEntry: Identifiable, Equatable, Sendable {
    let id: String
    let ordinal: Int
    let preview: String
}

/// One lightweight row returned by the session index query: the message id and
/// only the beginning of its text, so a megabyte paste never has to be read
/// just to draw a 100-character tooltip.
struct UserMessageIndexRecord: Equatable, Sendable {
    let id: String
    let contentPrefix: String
    /// True when the stored text is longer than `contentPrefix`.
    let isTruncated: Bool
}
