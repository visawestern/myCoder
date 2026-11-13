import Foundation

/// Pre-write module budget for model-driven code edits.
///
/// Directive 2026-11-13: a code edit must never leave a source file above
/// 600 physical lines. The executor asks this type before touching disk; a
/// refusal is returned to the model with the exact path, the resulting line
/// count and the required next step (split the file logically, update
/// imports/references/call sites, then retry).
enum FileLengthGuardLogic {

    /// Maximum physical lines for a source file.
    static let lineLimit = 600

    /// Source-file extensions covered by the module budget. Documentation,
    /// data and configuration files are intentionally excluded: the rule is
    /// about code modules, not about generated reports or plans.
    static let sourceExtensions: Set<String> = [
        "asm", "bash", "c", "cc", "cjs", "clj", "cljc", "cljs", "cpp", "cs",
        "cxx", "dart", "edn", "elm", "erl", "ex", "exs", "fish", "fs", "fsx",
        "go", "gradle", "groovy", "h", "hpp", "hrl", "hs", "htm", "html",
        "java", "jl", "js", "jsx", "kt", "kts", "less", "lhs", "lua", "m",
        "mjs", "mm", "mts", "nim", "php", "pl", "pm", "ps1", "py", "r", "rb",
        "rs", "s", "sass", "scala", "scss", "sh", "sol", "sql", "svelte",
        "swift", "ts", "tsx", "v", "vb", "vue", "zig", "zsh"
    ]

    /// Physical line count, same definition as `wc -l` and the repository's
    /// `ModuleSizeRatchetTests`: the number of newline characters.
    /// Input: file text. Output: newline count. Dependencies: none.
    static func lineCount(_ text: String) -> Int {
        text.utf8.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    /// Whether a path names a source file covered by the module budget.
    /// Input: project-relative or absolute path. Output: true for a known
    /// code extension (case-insensitive). Dependencies: none.
    static func isSourceFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return sourceExtensions.contains(ext)
    }

    /// Refusal for a mutation that would leave a source file over budget.
    /// Input: the tool name, the display path and the full resulting text.
    /// Output: nil when the mutation is allowed; otherwise an actionable
    /// `error:` line. Dependencies: `isSourceFile`, `lineCount`.
    static func refusal(action: String, path: String, content: String) -> String? {
        guard isSourceFile(path) else { return nil }
        let lines = lineCount(content)
        guard lines > lineLimit else { return nil }
        return """
        error: \(action) refused — \(path) would become \(lines) lines, over the \(lineLimit)-line module budget. \
        Split it logically now: move cohesive types/functions into new files, keep \(path) as the entry point, \
        update imports, references and call sites, then retry this edit. Do not delete working code to shorten it.
        """
    }
}
