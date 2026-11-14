import SwiftUI

/// Visual contract of the tool-approval card. A destructive shell command
/// (`rm -rf`, `rsync --delete`, `migrate --force`, `DROP TABLE`, …) gets the
/// RED card — red triangle with an exclamation mark, red border, red
/// "Run anyway" — even at Full access (user directive 2026-11-14, after a
/// production database was wiped without a question). An ordinary restricted
/// tool keeps the amber shield card.
struct ApprovalCardPresentation: Equatable {
    let isDestructive: Bool

    /// SF Symbol shown in the header.
    var iconName: String {
        isDestructive ? "exclamationmark.triangle.fill" : "exclamationmark.shield"
    }

    /// Localization key of the header title.
    var titleKey: String {
        isDestructive ? "locDestructiveCommandTitle" : "myCoder wants to run a restricted tool"
    }

    /// Localization key of the extra red warning, or nil for ordinary tools.
    var warningKey: String? {
        isDestructive ? "locDestructiveCommandWarning" : nil
    }

    /// Localization key of the Allow button ("Run anyway" when destructive).
    var allowTitleKey: String {
        isDestructive ? "locDestructiveRunAnyway" : "Allow"
    }

    /// Icon/title colour.
    var accentColor: Color {
        isDestructive ? Color.mimo.danger : Color.mimo.warning
    }

    /// Card border colour.
    var borderColor: Color {
        isDestructive ? Color.mimo.danger : Color.mimo.warning.opacity(0.6)
    }

    /// Card border width; the destructive card is deliberately heavier.
    var borderWidth: CGFloat {
        isDestructive ? 1.5 : 1
    }

    /// Card fill colour.
    var backgroundColor: Color {
        isDestructive ? Color.mimo.danger.opacity(0.08) : Color.mimo.surface.opacity(0.9)
    }

    /// Allow-button fill colour.
    var allowBackgroundColor: Color {
        isDestructive ? Color.mimo.danger : Color.mimo.success
    }
}
