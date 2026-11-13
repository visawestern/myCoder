import Foundation

/// Убирает из видимого текста сырые блоки протоколов вызова инструментов и
/// служебные статус-строки.
///
/// Живой дефект 2026-11-09: DSML-вызовы исполнялись (tool-call части с
/// результатами были), но сам `<｜DSML｜ calls>…</｜DSML｜ calls>` оставался в
/// `content` и показывался как ответ — вместе с «⏳ Running tools...».
/// Чистился только ```tool, поэтому DSML/Anthropic/function_call протекали
/// в пузырь. Вызовы должны жить в tool-call частях, а не в тексте.
enum ToolProtocolStripping {

    /// Полный видимый текст: без блоков вызовов, без статус-строк, без
    /// лишних пустых строк.
    static func visibleText(from text: String) -> String {
        guard !text.isEmpty else { return text }
        var out = text

        // DSML: сначала обёртка <calls> (внутри неё лежат invoke), затем
        // одиночные invoke без обёртки. Скобки бывают полнойширинными (｜).
        out = removeBlocks(out,
                           open: "<[|｜]?DSML[|｜]?\\s*calls\\s*>",
                           close: "</[|｜]?DSML[|｜]?\\s*calls\\s*>")
        out = removeBlocks(out,
                           open: "<[|｜]?DSML[|｜]?\\s*invoke\\s+[^>]*>",
                           close: "</[|｜]?DSML[|｜]?\\s*invoke\\s*>")

        // Anthropic-style блоки.
        out = removeBlocks(out, open: "<function_calls\\s*>", close: "</function_calls\\s*>")
        out = removeBlocks(out, open: "<tool_use\\s*>", close: "</tool_use\\s*>")
        out = removeBlocks(out, open: "<function_call\\b[^>]*>", close: "</function_call\\s*>")
        out = removeSelfClosingTags(out, pattern: "<function_call\\b[^>]*/>")

        // ERNIE-style <ernie:tool_call>…</ernie:tool_call> и одиночные <invoke>.
        out = removeBlocks(out, open: "<ernie:tool_call\\b[^>]*>", close: "</ernie:tool_call\\s*>")
        out = removeBlocks(out, open: "<invoke\\b[^>]*>", close: "</invoke\\s*>")

        // ```tool fences — тем же правилом, что и раньше.
        out = WebToolProtocolEmulator.strippingToolFences(from: out)

        out = stripStatusLines(out)
        return collapseBlankLines(out)
    }

    /// Есть ли в тексте хоть один блок вызова инструмента.
    static func containsToolProtocol(_ text: String) -> Bool {
        visibleText(from: text) != collapseBlankLines(text)
    }

    // MARK: - Blocks

    private static func removeBlocks(_ text: String, open: String, close: String) -> String {
        let pattern = "\(open)[\\s\\S]*?\(close)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func removeSelfClosingTags(_ text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    // MARK: - Status lines

    /// Служебные строки, которые не являются ответом модели: «⏳ Running
    /// tools...», «Waiting for X to respond…», «Thinking… (model)»,
    /// «Sent via …». Убираем строку целиком, а не только маркер.
    private static func stripStatusLines(_ text: String) -> String {
        let kept = text.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            if trimmed.contains("⏳") || trimmed.contains("Running tools") { return false }
            if trimmed.hasPrefix("Waiting for "), trimmed.contains("to respond") { return false }
            if trimmed.hasPrefix("Thinking… (") { return false }
            if trimmed.hasPrefix("Sent via ") { return false }
            return true
        }
        return kept.joined(separator: "\n")
    }

    private static func collapseBlankLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
