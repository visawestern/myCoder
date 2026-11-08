import Foundation

/// Decides what the "Контекст" sheet shows for one message.
///
/// The content is derived from the message itself — the persisted
/// `.compiledContext` part and `contextSummary` — never from transient view
/// state. A message row can be recreated by scrolling, a session can be
/// reloaded, and a sheet can be presented a frame later; local `@State` can be
/// empty exactly when the sheet reads it. The message cannot.
enum MessageContextSheetLogic {

    struct Content: Equatable, Sendable {
        /// The full compiled payload (system instruction + evidence + request).
        let text: String
        /// Honest reason why there is no pack, when the message carries one.
        let fallback: String?

        var displayText: String {
            if !text.isEmpty { return text }
            if let fallback, !fallback.isEmpty { return fallback }
            return "Контекст не собран."
        }
    }

    static func content(compiledContextText: String?, summary: String?) -> Content {
        let text = compiledContextText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Content(
            text: text,
            fallback: trimmedSummary.isEmpty ? nil : trimmedSummary
        )
    }

    static func content(for message: Message) -> Content {
        content(
            compiledContextText: compiledContext(in: message.parts),
            summary: message.contextSummary
        )
    }

    /// The first non-empty compiled-context part. Empty parts are treated as
    /// absent so an empty placeholder can never shadow a real pack.
    static func compiledContext(in parts: [MessagePartContent]) -> String? {
        for part in parts {
            if case .compiledContext(let text) = part {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return text }
            }
        }
        return nil
    }
}
