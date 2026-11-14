import AppKit
import SwiftUI

/// Process-local storage for `CodeSyntaxHighlighter.cachedAttributed`.
///
/// Lives outside the highlighter enum because Swift extensions cannot hold
/// stored properties. Everything here is RAM-only: the entries die with the
/// process, nothing is written to disk.
///
/// Inputs: written only through `CodeSyntaxHighlighter.cachedAttributed`.
/// Outputs: dictionary lookups guarded by `lock`.
/// Dependencies: `AttributedString`, `NSLock`.
private enum CodeHighlightCacheStore {
    /// Highlighted runs keyed by (code, language, palette signature).
    static var entries: [CodeHighlightKey: AttributedString] = [:]
    /// Recency order, oldest first. A hit moves its key to the end.
    static var order: [CodeHighlightKey] = []
    /// Number of lookups served from memory.
    static var hits = 0
    /// Number of full tokenize+colour passes performed.
    static var builds = 0
    /// Guards every field above; the highlighter is usable from any thread.
    static let lock = NSLock()
}

/// Identity of one highlighted block: same source text, same fence language
/// and same colours produce the same attributed string, so the renderer may
/// reuse the previous result instead of re-tokenizing on every `body` pass.
private struct CodeHighlightKey: Hashable {
    let code: String
    let language: String
    let palette: String
}

extension CodeSyntaxHighlighter {

    /// Upper bound on retained blocks. This is a cache size, not a memory
    /// fuse: one chat screen shows far fewer code blocks than this, and the
    /// LRU order drops the coldest entry first.
    static let highlightCacheLimit = 512

    /// Highlighted attributed string, reused when the exact same block was
    /// highlighted before.
    ///
    /// - Parameters:
    ///   - code: verbatim fence body, byte-for-byte as shown.
    ///   - language: fence language identifier (may be empty).
    ///   - palette: resolved code palette; a different palette is a different
    ///     entry because the colours are baked into the result.
    /// - Returns: the same value `attributed(_:language:palette:)` produces.
    /// - Side effects: bumps `highlightHits` on a hit, `highlightBuilds` on a
    ///   miss, and may evict the oldest entry when the cache is full.
    static func cachedAttributed(
        _ code: String,
        language: String,
        palette: CodePalette
    ) -> AttributedString {
        // Нормализация языка: `swift`, `Swift` и ` SWIFT ` — один ключ
        // кэша (одна и та же подсветка).
        let normalizedLanguage = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let key = CodeHighlightKey(
            code: code,
            language: normalizedLanguage,
            palette: paletteSignature(palette)
        )

        CodeHighlightCacheStore.lock.lock()
        if let cached = CodeHighlightCacheStore.entries[key] {
            CodeHighlightCacheStore.hits += 1
            touchLocked(key)
            CodeHighlightCacheStore.lock.unlock()
            return cached
        }
        CodeHighlightCacheStore.lock.unlock()

        let built = attributed(code, language: language, palette: palette)

        CodeHighlightCacheStore.lock.lock()
        CodeHighlightCacheStore.builds += 1
        if CodeHighlightCacheStore.entries[key] == nil {
            CodeHighlightCacheStore.entries[key] = built
            CodeHighlightCacheStore.order.append(key)
            evictLocked()
        }
        CodeHighlightCacheStore.lock.unlock()
        return built
    }

    /// Number of highlighted blocks served from memory since the last reset.
    static var highlightHits: Int {
        CodeHighlightCacheStore.lock.lock()
        defer { CodeHighlightCacheStore.lock.unlock() }
        return CodeHighlightCacheStore.hits
    }

    /// Number of full highlight passes performed since the last reset.
    static var highlightBuilds: Int {
        CodeHighlightCacheStore.lock.lock()
        defer { CodeHighlightCacheStore.lock.unlock() }
        return CodeHighlightCacheStore.builds
    }

    /// Drops every cached block and zeroes both counters. Used by tests and
    /// after a theme change that makes old palettes unreachable.
    static func resetHighlightCache() {
        CodeHighlightCacheStore.lock.lock()
        CodeHighlightCacheStore.entries.removeAll()
        CodeHighlightCacheStore.order.removeAll()
        CodeHighlightCacheStore.hits = 0
        CodeHighlightCacheStore.builds = 0
        CodeHighlightCacheStore.lock.unlock()
    }

    // MARK: - Private

    /// Marks `key` as the most recently used entry. Caller holds the lock.
    private static func touchLocked(_ key: CodeHighlightKey) {
        if let index = CodeHighlightCacheStore.order.firstIndex(of: key) {
            CodeHighlightCacheStore.order.remove(at: index)
        }
        CodeHighlightCacheStore.order.append(key)
    }

    /// Drops the coldest entries until the cache fits `highlightCacheLimit`.
    /// Caller holds the lock.
    private static func evictLocked() {
        while CodeHighlightCacheStore.order.count > highlightCacheLimit {
            let victim = CodeHighlightCacheStore.order.removeFirst()
            CodeHighlightCacheStore.entries.removeValue(forKey: victim)
        }
    }

    /// Stable textual fingerprint of a palette.
    ///
    /// `Color` is `Equatable` but not `Hashable`, so the cache key carries the
    /// resolved sRGB components of every slot. Two palettes that render
    /// identically therefore share an entry, and a real colour change always
    /// produces a different key.
    private static func paletteSignature(_ palette: CodePalette) -> String {
        let slots: [Color] = [
            palette.background, palette.headerBackground, palette.border,
            palette.text, palette.comment, palette.keyword, palette.string,
            palette.number, palette.function, palette.type, palette.constant,
            palette.decorator, palette.lineNumber, palette.diffAdded,
            palette.diffRemoved, palette.diffMeta
        ]
        return slots.map(componentSignature).joined(separator: ",")
    }

    /// Comma-free `r/g/b/a` signature of one colour, rounded to 1/10000 so
    /// float noise cannot split an entry in two.
    private static func componentSignature(_ color: Color) -> String {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            return "?"
        }
        let values = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
        return values
            .map { String(format: "%.4f", Double($0)) }
            .joined(separator: "/")
    }
}
