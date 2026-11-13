import Foundation

/// Дополнительные реальные форматы вызовов инструментов, которые модели
/// эмитят в тексте ответа помимо наших ```tool-блоков. Каждый парсер —
/// чистая маленькая функция, покрытая тестами (ExtraToolCallFormatParsersTests).
///
/// Покрытые форматы:
/// 1. Anthropic/Claude классический: `<function_calls><invoke name="…">
///    <parameter name="…">v</parameter></invoke></function_calls>` (и одиночные
///    <invoke> без обёртки).
/// 2. Anthropic/Claude новый: `<tool_use name="…"><input>…</input></tool_use>`,
///    где input — либо JSON-объект аргументов, либо `key=value` пары.
/// 3. `<function_call name="…" arguments='{json}'>` и вариант с вложенными
///    `<param name="…">v</param>`.
enum ExtraToolCallFormatParsers {

    /// Все дополнительные форматы сразу.
    static func parseAll(from text: String) -> [WebToolCall] {
        var calls: [WebToolCall] = []
        calls.append(contentsOf: parseAnthropicInvokeCalls(from: text))
        calls.append(contentsOf: parseToolUseCalls(from: text))
        calls.append(contentsOf: parseFunctionCallTagCalls(from: text))
        calls.append(contentsOf: parseErnieToolCalls(from: text))
        return calls
    }

    // MARK: - ERNIE <ernie:tool_call>…</ernie:tool_call>

    /// Parses `<ernie:tool_call>` wrappers whose body is either JSON
    /// `{"name":…, "args":…}` or inner `<invoke>` tags (deduped downstream).
    static func parseErnieToolCalls(from text: String) -> [WebToolCall] {
        guard text.contains("<ernie:tool_call") else { return [] }
        guard let regex = try? NSRegularExpression(
            pattern: "<ernie:tool_call\\b[^>]*>([\\s\\S]*?)</ernie:tool_call\\s*>",
            options: [.caseInsensitive]) else { return [] }
        let scanner = text as NSString
        var calls: [WebToolCall] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        where match.numberOfRanges >= 2 {
            let body = scanner.substring(with: match.range(at: 1))
            let nested = parseAnthropicInvokeCalls(from: body)
            if !nested.isEmpty {
                calls.append(contentsOf: nested)
            } else if let jsonCall = WebToolProtocolEmulator.parseSingleCall(body) {
                calls.append(jsonCall)
            }
        }
        return calls
    }

    // MARK: - Anthropic <invoke name><parameter>

    static func parseAnthropicInvokeCalls(from text: String) -> [WebToolCall] {
        guard let regex = try? NSRegularExpression(
            pattern: "<invoke\\s+([^>]*)>(.*?)</invoke>",
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
            calls.append(WebToolCall(name: canonical, arguments: parseChildParameterBodies(in: body)))
        }
        return calls
    }

    // MARK: - Anthropic <tool_use name><input>

    static func parseToolUseCalls(from text: String) -> [WebToolCall] {
        guard let regex = try? NSRegularExpression(
            pattern: "<tool_use\\s+([^>]*)>(.*?)</tool_use>",
            options: [.dotMatchesLineSeparators]) else { return [] }
        let scanner = text as NSString
        var calls: [WebToolCall] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        where match.numberOfRanges >= 3 {
            let openTag = scanner.substring(with: match.range(at: 1))
            let body = scanner.substring(with: match.range(at: 2))
            guard let rawName = attributeValue(named: "name", in: openTag),
                  let canonical = WebToolProtocolEmulator.canonicalToolName(rawName),
                  let inputBody = inputElementBody(in: body) else {
                continue
            }
            calls.append(WebToolCall(name: canonical, arguments: decodeInputBody(inputBody)))
        }
        return calls
    }

    // MARK: - <function_call name="…" arguments="{json}"> / <param>

    static func parseFunctionCallTagCalls(from text: String) -> [WebToolCall] {
        guard let regex = try? NSRegularExpression(
            pattern: "<function_call\\s+([^>]*)>(.*?)</function_call>",
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
            var arguments: [String: String] = [:]
            // Аргументы могут быть атрибутом: args="{json}" / arguments="{json}".
            if let jsonString = attributeValue(named: "arguments", in: openTag)
                ?? attributeValue(named: "args", in: openTag) {
                arguments = decodeJSONObjectString(jsonString)
            }
            if arguments.isEmpty {
                arguments = parseChildParameterBodies(in: body)
            }
            calls.append(WebToolCall(name: canonical, arguments: arguments))
        }
        return calls
    }

    // MARK: - Общие помощники

    /// Вложенные `<param name="k">v</param>` / `<parameter name="k">v</parameter>`.
    private static func parseChildParameterBodies(in body: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: "<(?:param|parameter)\\s+([^>]*)>([\\s\\S]*?)</(?:param|parameter)\\s*>",
            options: [.dotMatchesLineSeparators]) else { return [:] }
        let scanner = body as NSString
        var args: [String: String] = [:]
        for match in regex.matches(in: body, range: NSRange(location: 0, length: scanner.length))
        where match.numberOfRanges >= 3 {
            let openTag = scanner.substring(with: match.range(at: 1))
            let value = scanner.substring(with: match.range(at: 2))
            guard let key = attributeValue(named: "name", in: openTag) else { continue }
            args[key] = DSMLToolCallParser.decodeHTMLEntities(value)
        }
        return args
    }

    /// Тело `<input>…</input>` (без тегов).
    private static func inputElementBody(in body: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<input>([\\s\\S]*?)</input>",
            options: [.dotMatchesLineSeparators]) else { return nil }
        let scanner = body as NSString
        guard let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: scanner.length)),
              match.numberOfRanges >= 2 else { return nil }
        return scanner.substring(with: match.range(at: 1))
    }

    /// `<input>` может быть JSON-объектом аргументов либо `key=value` парами.
    private static func decodeInputBody(_ input: String) -> [String: String] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            let json = decodeJSONObjectString(trimmed)
            if !json.isEmpty { return json }
        }
        return parseKVPairs(trimmed)
    }

    /// Распарсить JSON-объект `{"k": "v", ...}` в [String: String].
    private static func decodeJSONObjectString(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var args: [String: String] = [:]
        for (key, value) in obj {
            if let s = value as? String {
                args[key] = s
            } else if let num = value as? NSNumber, CFGetTypeID(num) == CFBooleanGetTypeID() {
                args[key] = num.boolValue ? "true" : "false"
            } else {
                args[key] = "\(value)"
            }
        }
        return args
    }

    /// `key=value` пары (значения могут быть в кавычках).
    private static func parseKVPairs(_ text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: "([A-Za-z_][A-Za-z0-9_.-]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|(\\S+))") else {
            return [:]
        }
        let scanner = text as NSString
        var args: [String: String] = [:]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        where match.numberOfRanges >= 6 {
            guard let key = match.range(at: 1).location != NSNotFound
                ? scanner.substring(with: match.range(at: 1))
                : nil else { continue }
            let value = substring(at: 3, in: match, of: scanner)
                ?? substring(at: 4, in: match, of: scanner)
                ?? substring(at: 5, in: match, of: scanner)
                ?? ""
            args[key] = value
        }
        return args
    }

    private static func substring(at index: Int, in match: NSTextCheckingResult,
                                  of scanner: NSString) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return scanner.substring(with: range)
    }

    /// Значение атрибута `name="…"` из открывающего тега. Поддерживаются и
    /// двойные, и одинарные кавычки (`arguments='{"a": "b"}'`).
    private static func attributeValue(named name: String, in openTag: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: openTag, range: NSRange(location: 0, length: (openTag as NSString).length)) else {
            return nil
        }
        let scanner = openTag as NSString
        if match.numberOfRanges >= 2, match.range(at: 1).location != NSNotFound {
            return scanner.substring(with: match.range(at: 1))
        }
        if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
            return scanner.substring(with: match.range(at: 2))
        }
        return nil
    }
}
