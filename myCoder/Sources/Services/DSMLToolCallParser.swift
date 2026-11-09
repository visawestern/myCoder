import Foundation

/// Парсер XML-подобного протокола вызовов инструментов «DSML», который
/// часть моделей (DeepSeek V4.1 Flash / MiMo-style агенты) эмитят вместо
/// наших ```tool-блоков. Live-дефект 2026-11-09: чат завис на
/// `<｜DSML｜ invoke …>` — вызов не исполнялся, ответ показывался как текст.
///
/// Синтаксис (пример из живого чата):
///
///   <｜DSML｜ calls>
///     <｜DSML｜ invoke name="list_dir">
///       <｜DSML｜ parameter name="path" string="true">.</｜DSML｜ parameter>
///     </｜DSML｜ invoke>
///   </｜DSML｜ calls>
///
/// Парсер толерантен:
/// - к вариантам скобок: полнойширинные ｜DSML｜, обычные |DSML|, без скобок DSML;
/// - к отсутствию обёртки <calls> — серия одиночных <invoke> тоже работает;
/// - к HTML-entities в значениях (&amp; &lt; &gt; &quot; &#39;).
enum DSMLToolCallParser {

    static func parseCalls(from text: String) -> [WebToolCall] {
        // Полнойшириная вертикальная черта (U+FF5C) → обычная |, чтобы
        // один паттерн покрывал все варианты скобок.
        let normalized = text.replacingOccurrences(of: "\u{FF5C}", with: "|")
        return parseInvokeBodies(in: normalized)
    }

    /// Найти все тела `<|DSML| invoke …>…</|DSML| invoke>`.
    private static func parseInvokeBodies(in text: String) -> [WebToolCall] {
        guard let regex = try? NSRegularExpression(
            pattern: "<\\|?DSML\\|?\\s+invoke\\s+([^>]*)>(.*?)</\\|?DSML\\|?\\s+invoke\\s*>",
            options: [.dotMatchesLineSeparators]) else { return [] }
        let scanner = text as NSString
        var calls: [WebToolCall] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        where match.numberOfRanges >= 3 {
            let openTag = scanner.substring(with: match.range(at: 1))
            let body = scanner.substring(with: match.range(at: 2))
            guard let rawName = attributeValue(named: "name", in: openTag),
                  let canonical = WebToolProtocolEmulator.canonicalToolName(rawName) else {
                continue
            }
            calls.append(WebToolCall(name: canonical, arguments: parseParameterBodies(in: body)))
        }
        return calls
    }

    /// Извлечь параметры `<|DSML| parameter name="k" …>v</|DSML| parameter>`.
    private static func parseParameterBodies(in body: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: "<\\|?DSML\\|?\\s+parameter\\s+([^>]*)>([\\s\\S]*?)</\\|?DSML\\|?\\s+parameter\\s*>",
            options: [.dotMatchesLineSeparators]) else { return [:] }
        let scanner = body as NSString
        var args: [String: String] = [:]
        for match in regex.matches(in: body, range: NSRange(location: 0, length: scanner.length))
        where match.numberOfRanges >= 3 {
            let openTag = scanner.substring(with: match.range(at: 1))
            let value = scanner.substring(with: match.range(at: 2))
            guard let key = attributeValue(named: "name", in: openTag) else { continue }
            args[key] = decodeHTMLEntities(value)
        }
        return args
    }

    /// Достать значение атрибута `name="…"` из открывающего тега.
    private static func attributeValue(named name: String, in openTag: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: openTag, range: NSRange(location: 0, length: (openTag as NSString).length)),
              match.numberOfRanges >= 2 else { return nil }
        return (openTag as NSString).substring(with: match.range(at: 1))
    }

    /// Раскрыть HTML-entities в значениях параметров.
    static func decodeHTMLEntities(_ value: String) -> String {
        var out = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        // Числовые entities &#NN; (и &#xHH;).
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let scanner = out as NSString
            var converted = out
            var offset = 0
            for match in regex.matches(in: out, range: NSRange(location: 0, length: scanner.length))
            where match.numberOfRanges >= 3 {
                let isHex = scanner.substring(with: match.range(at: 1)).lowercased() == "x"
                let digits = scanner.substring(with: match.range(at: 2))
                guard let scalar = isHex
                    ? UInt32(digits, radix: 16)
                    : UInt32(digits),
                    let unicode = UnicodeScalar(scalar) else { continue }
                let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
                if let range = Range(fullRange, in: converted) {
                    converted.replaceSubrange(range, with: String(unicode))
                    offset += String(unicode).count - match.range.length
                }
            }
            out = converted
        }
        return out
    }
}
