import Foundation

/// Chat titles derived from the request text (no model call: instant,
/// offline, zero tokens). A local generative model may refine these later;
/// this heuristic is the floor that always produces a distinct, readable row.
enum ChatTitleLogic {
    /// Maximum title length including any dedup suffix.
    static let maxLength = 60
    /// Words taken from the head of the request.
    static let maxWords = 8

    /// Title for `text`, unique against `existingTitles` ("New Chat" fallback).
    static func title(for text: String, existingTitles: [String] = []) -> String {
        let words = tokenize(text).prefix(maxWords)
        guard !words.isEmpty else { return "New Chat" }
        var base = words.joined(separator: " ")
        if base.count > maxLength {
            base = String(base.prefix(maxLength))
            if let lastSpace = base.lastIndex(of: " ") {
                base = String(base[..<lastSpace])
            }
        }
        if !existingTitles.contains(base) { return base }
        var n = 2
        while existingTitles.contains("\(base) \(n)") { n += 1 }
        var suffixed = "\(base) \(n)"
        if suffixed.count > maxLength + 4 {
            suffixed = String(base.prefix(maxLength)) + " \(n)"
        }
        return suffixed
    }

    /// Lowercased? No — keep the user's casing. Split on whitespace,
    /// drop empties, strip leading command punctuation from the first token.
    static func tokenize(_ text: String) -> [String] {
        var tokens = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard var first = tokens.first else { return [] }
        while let c = first.first, "!/?@#$".contains(c) {
            first.removeFirst()
        }
        if first.isEmpty {
            tokens.removeFirst()
        } else {
            tokens[0] = first
        }
        return tokens
    }
}
