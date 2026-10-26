import Foundation

/// Keeps the user's explicit chat-input choices (provider/model) sticky across
/// restarts and server reconnects: a temporary fallback must never overwrite
/// the preference, and the preference is restored as soon as it is available.
enum SelectionRestoreLogic {

    /// Returns the provider that should be selected, or nil when no change is needed.
    static func resolvedProviderID(preferred: String, current: String, options: [String]) -> String? {
        guard !preferred.isEmpty, preferred != current, options.contains(preferred) else { return nil }
        return preferred
    }

    static func resolvedModelID(preferred: String, current: String, options: [String]) -> String? {
        resolvedProviderID(preferred: preferred, current: current, options: options)
    }
}
