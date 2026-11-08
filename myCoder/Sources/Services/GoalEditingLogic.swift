import Foundation

/// Rules for changing a goal's title.
///
/// The title is user text: it is trimmed, it may not be empty, and it is
/// capped so a pasted paragraph cannot break the one-line card.
enum GoalEditingLogic {

    /// Longest goal title the sidebar shows.
    static let maxTitleLength = 200

    /// The title to store, or nil when the user gave nothing usable.
    static func normalizedTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxTitleLength))
    }
}
