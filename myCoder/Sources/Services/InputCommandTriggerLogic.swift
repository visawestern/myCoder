import Foundation

/// Pure, UI-independent logic that detects when the user has typed a trigger
/// (`/`, `@`, `#`, optionally `$`) at the start of a word inside the input
/// field, and extracts the live filter text for the dropdown (plan Раздел 6).
struct TriggerContext: Equatable {
    enum Source: Equatable { case commands, files, sessions, mcp }

    let source: Source
    /// The trigger symbol, e.g. "/".
    let symbol: Character
    /// Index of the trigger symbol in the source string.
    let triggerIndex: Int
    /// Filter text typed after the trigger (may be empty).
    let filter: String
}

enum InputCommandTriggerLogic {
    /// Map trigger symbols to their data source. `$` lists configured MCP servers
    /// (INP-16); it is enabled by default and safe when no servers are configured
    /// (an empty server list yields no dropdown, matching the other sources).
    static var enabledSymbols: Set<Character> = ["/", "@", "#", "$"]

    /// Returns a trigger context if `text` contains a valid trigger at/around
    /// `cursorPosition`, else nil. A trigger is valid when the symbol sits at
    /// the start of the string or immediately after a whitespace character, so
    /// that mid-word text (e.g. `user@example.com`) does not fire.
    static func detectTrigger(text: String, cursorPosition: Int) -> TriggerContext? {
        guard cursorPosition > 0, cursorPosition <= text.count else { return nil }
        let chars = Array(text)
        // Walk back from the cursor to the trigger symbol, stopping at whitespace.
        var i = cursorPosition - 1
        // Skip and collect the filter substring (everything between trigger and cursor).
        while i >= 0 {
            let c = chars[i]
            if c.isWhitespace { return nil }     // no trigger before a space going back
            if enabledSymbols.contains(c) {
                // Valid only if trigger is at start or preceded by whitespace.
                let prev = i == 0 ? nil : chars[i - 1]
                if let prev = prev, !prev.isWhitespace {
                    return nil                   // mid-word trigger (email-like), ignore
                }
                let filter = String(chars[(i + 1)..<cursorPosition])
                return TriggerContext(source: source(for: c),
                                      symbol: c,
                                      triggerIndex: i,
                                      filter: filter)
            }
            i -= 1
        }
        return nil
    }

    /// True when the trigger should remain open for the given new text/cursor,
    /// i.e. the trigger symbol still exists and no whitespace/enter broke the
    /// word. Convenience for cancel-on-space logic.
    static func shouldDismiss(after context: TriggerContext, text: String, cursorPosition: Int) -> Bool {
        guard cursorPosition > 0, cursorPosition <= text.count else { return true }
        let chars = Array(text)
        guard context.triggerIndex < chars.count else { return true }
        guard chars[context.triggerIndex] == context.symbol else { return true }
        // Dismiss if a whitespace appeared between trigger and cursor.
        if cursorPosition > context.triggerIndex + 1 {
            for c in chars[(context.triggerIndex + 1)..<cursorPosition] where c.isWhitespace {
                return true
            }
        }
        return false
    }

    private static func source(for symbol: Character) -> TriggerContext.Source {
        switch symbol {
        case "/": return .commands
        case "@": return .files
        case "#": return .sessions
        case "$": return .mcp
        default: return .commands
        }
    }
}

/// Unified dropdown item model (plan Раздел 6 Блок 1 п.9) shared by all
/// trigger sources so the view layer renders one shape.
struct CommandDropdownItem: Identifiable, Equatable {
    enum Kind: Equatable { case command, skill, mcp, file, session }
    let id: String
    let title: String
    let subtitle: String
    let category: String
    let icon: String
    let kind: Kind
    /// Optional payload for the action handler (e.g. slash command name).
    let actionKey: String?
}

/// Fuzzy + prefix matching for the dropdown (plan Раздел 6 Блок 5 п.43).
enum CommandDropdownFilter {
    /// Returns items whose title or subtitle prefix-matches or fuzzy-matches
    /// the filter (case-insensitive). Prefix matches rank above fuzzy matches.
    static func filter(_ items: [CommandDropdownItem], query: String) -> [CommandDropdownItem] {
        let q = query.lowercased()
        guard !q.isEmpty else { return items }
        var prefix: [CommandDropdownItem] = []
        var fuzzy: [CommandDropdownItem] = []
        for item in items {
            let title = item.title.lowercased()
            if title.hasPrefix(q) || item.category.lowercased().hasPrefix(q) {
                prefix.append(item)
            } else if fuzzyMatch(q, in: title) || fuzzyMatch(q, in: item.subtitle.lowercased()) {
                fuzzy.append(item)
            }
        }
        return prefix + fuzzy
    }

    /// Simple subsequence fuzzy match: every char of `needle` appears in `haystack`
    /// in order (case handled by caller lowercasing both sides).
    static func fuzzyMatch(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var needleIterator = needle.makeIterator()
        var current = needleIterator.next()
        for char in haystack where current != nil {
            if char == current {
                current = needleIterator.next()
            }
        }
        return current == nil
    }
}
