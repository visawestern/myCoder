import Foundation

/// Audit 2026-09-12 (last chat, session C9AB8206): vendor code-block chrome
/// is scraped into the model answer together with its real content. Kimi
/// renders every fenced block with a language chip ("tool" for our
/// ```tool fences) and a copy button whose localized label ("Копировать" /
/// "Copy" / "コピー") lands in innerText as a standalone line:
///
///     tool
///     Копировать
///     {"name": "list_dir", "args": {"path": "."}}
///
/// The tool-call parser already tolerates the surrounding noise, but the
/// FINAL answer shown to the user and saved to the database carried the
/// junk lines verbatim (live: every emitted block in the saved message was
/// prefixed with "tool\nКопировать"). This sanitizer strips that chrome
/// AFTER the tool calls were extracted, so parsing is unaffected but the
/// stored/displayed text is clean.
enum WebScrapedTextSanitizer {

    /// Localized copy-button labels vendors render inside code chrome.
    /// Matched as STANDALONE LINES only (a paragraph legitimately containing
    /// the word "Copy" is never touched).
    static let copyChipLabels: Set<String> = [
        "копировать",
        "copy",
        "copiar",
        "copier",
        "kopieren",
        "复制",
        "コピー",
        "복사",
        "copiar",
        "نسخ",
        "copiare",
    ]

    /// Language-chip labels our own tool protocol can produce. ```tool
    /// fences are also parsed by the emulator, but when a fence is shown
    /// INLINE in a final answer (the model explains a call it already made)
    /// the chip line stays as junk. Stripped as standalone lines only.
    static let fenceChipLabels: Set<String> = [
        "tool",
        "tool_result",
        "bash",
        "sh",
        "shell",
        "json",
        "plain",
        "plaintext",
        "text",
        "code",
    ]

    /// True when the whole (trimmed, lowercased) line is exactly a chrome
    /// label — never matches the label embedded inside real prose.
    private static func isStandaloneChipLine(_ rawLine: String) -> Bool {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !line.isEmpty else { return false }
        // Chrome chips are 1–2 words; a longer line is prose even when it
        // starts with a chip word.
        guard line.count <= 12 else { return false }
        return copyChipLabels.contains(line) || fenceChipLabels.contains(line)
    }

    /// Remove vendor code-chrome junk lines from a scraped answer.
    /// Fence delimiters (```) are PRESERVED — markdown rendering needs them
    /// and the tool parser runs before/after this on the raw text.
    /// Chip lines are dropped only when they stand alone on their own line;
    /// surrounding blank-line runs are collapsed so removal leaves no gaps.
    static func stripChromeLines(from text: String) -> String {
        guard !text.isEmpty else { return text }
        var kept: [String] = []
        var lastWasBlank = false
        for rawLine in text.components(separatedBy: "\n") {
            if isStandaloneChipLine(rawLine) { continue }
            let isBlank = rawLine.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && lastWasBlank { continue }
            kept.append(rawLine)
            lastWasBlank = isBlank
        }
        var result = kept.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A fence whose body was fully chrome-only (e.g. "```\ntool\nКопировать\n```")
        // becomes an empty fence — drop it.
        result = result
            .replacingOccurrences(of: "```\\s*```", with: "", options: .regularExpression)
            .replacingOccurrences(
                of: "\\n?```\\s*\\n\\s*```",
                with: "",
                options: .regularExpression
            )
        return result
    }

    /// Sanitize a FINAL model answer: strip chrome lines. Applied after the
    /// tool-call extraction in the driver, so the parser still sees raw
    /// blocks; the user-visible and persisted text stays clean.
    static func sanitizeAnswer(_ text: String) -> String {
        stripChromeLines(from: text)
    }

    /// Sanitize a STREAMING snapshot: same rules; safe to apply every poll
    /// because chip lines are idempotently removed and everything else is
    /// preserved byte-for-byte.
    static func sanitizeStreaming(_ text: String) -> String {
        stripChromeLines(from: text)
    }
}
