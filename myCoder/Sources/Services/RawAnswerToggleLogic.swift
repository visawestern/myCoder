import Foundation

/// The raw/formatted switch on a message (user directive 2026-11-03, п.3).
///
/// The old control existed to make a formatted answer selectable as one block
/// of plain text. That is no longer the job: the button now swaps the rendered
/// answer for the raw wire response and back, sitting next to resend/retry.
/// Pure, so the icon and availability rules are testable without the UI.
enum RawAnswerToggleLogic {

    /// Any message with something to show can be switched: a rendered answer,
    /// raw wire events, or both. An empty placeholder cannot.
    static func canToggle(messageText: String, rawEvents: [String]?) -> Bool {
        if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !(rawEvents ?? []).isEmpty
    }

    /// Formatted → raw shows a code icon; raw → formatted shows a text icon.
    static func icon(isRaw: Bool) -> String {
        isRaw ? "text.alignleft" : "chevron.left.forwardslash.chevron.right"
    }

    static func tooltipKey(isRaw: Bool) -> AppLocalizationKey {
        isRaw ? .locFormatted : .locRawText
    }

    static func toggled(isRaw: Bool) -> Bool {
        !isRaw
    }
}
