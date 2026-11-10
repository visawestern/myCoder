import Foundation

extension WebToolProtocolEmulator {
    /// Extract all tool calls from a model response. Tolerant of surrounding
    /// prose and markdown fences (plan Блок 2 п.11/п.13), and — since Round 12 —
    /// also of the informal `[tool call: NAME with args]` syntax that plain web
    /// models actually emit (e.g. `[tool call: LS with path "."]`), so the
    /// agentic loop never stalls on a well-meant but non-strict call.
    static func parseToolCalls(from responseText: String) -> [WebToolCall] {
        parseToolCallsWithIssues(from: responseText).calls
    }

    /// Remove complete ```tool … ``` fences from `text`. Tool calls render as
    /// their own spoiler parts, so leaving the raw fence in the answer text
    /// would duplicate it (user directive 2026-10-29). Non-tool fences and
    /// prose are left untouched.
    static func strippingToolFences(from text: String) -> String {
        guard text.contains("```tool") else { return text }
        let ns = text as NSString
        let pattern = "```tool\\s*\\n(.*?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        let stripped = regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )
        // A removed fence can leave a run of blank lines; collapse it.
        let collapsed = stripped.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Same parser, plus one report per tool block that could not become an
    /// executable call. A malformed block is never silently dropped: the
    /// driver turns each issue into a `tool_result` error for the model, so a
    /// single broken call cannot kill the rest of the turn.
    static func parseToolCallsWithIssues(
        from responseText: String
    ) -> (calls: [WebToolCall], issues: [WebToolCallParseIssue]) {
        var calls: [WebToolCall] = []
        var issues: [WebToolCallParseIssue] = []
        // Find ```tool ... ``` fenced blocks. The closing fence may directly
        // follow the JSON (no trailing newline) — tolerate that too.
        let scanner = responseText as NSString
        let pattern = "```tool\\s*\\n(.*?)\\s*```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let matches = regex.matches(in: responseText, range: NSRange(location: 0, length: scanner.length))
            for match in matches where match.numberOfRanges >= 2 {
                let jsonString = scanner.substring(with: match.range(at: 1))
                if let call = parseSingleCall(jsonString) {
                    calls.append(call)
                    continue
                }
                // A stream cut off mid-JSON is answered with "re-emit the
                // complete block" by the driver's truncated-call branch.
                if let stub = parseTruncatedToolCallStub(from: jsonString).first {
                    calls.append(stub)
                    continue
                }
                issues.append(WebToolCallParseIssue(
                    toolName: recoveredToolName(from: jsonString) ?? "tool",
                    reason: describeJSONProblem(jsonString),
                    raw: String(jsonString.prefix(400))
                ))
            }
        }
        // Then the informal `[tool call: NAME ...]` variant.
        calls.append(contentsOf: parseInformalCalls(from: responseText))
        // Then the XML `<NAME>k=v</NAME>` variant that big-pickle / MiMo-style models emit natively.
        calls.append(contentsOf: parseTaggedToolCalls(from: responseText))
        // Then the SHORT XML form the preamble itself teaches:
        // `<list_dir>path=.</list_dir>` (audit 2026-09-11, Kimi live: the
        // model emits exactly this, the verbose parser ignores it, and the
        // turn dies with raw tool text as the "answer").
        calls.append(contentsOf: parseShortTaggedCalls(from: responseText))
        // Then the XML-подобные форматы других модельных семей:
        // DSML <｜DSML｜ invoke name> (DeepSeek V4.1 Flash / MiMo-style),
        // Anthropic <function_calls><invoke><parameter>, <tool_use><input>,
        // <function_call name arguments="{json}"> (live 2026-11-09).
        calls.append(contentsOf: DSMLToolCallParser.parseCalls(from: responseText))
        calls.append(contentsOf: ExtraToolCallFormatParsers.parseAll(from: responseText))

        // Audit 2026-09-08 (Qwen live): reasoning streams can BREAK the fence
        // itself — the answer arrives as `tool\n1\n{"name":\u{00A0}"list_dir", ...}`
        // with no backticks at all. Scan for complete {"name": …, "args": {…}}
        // objects in the raw text (NBSP-normalized) before the truncated-stub
        // fallback, so a fully written call without fences still executes.
        // A broken *fenced* block must not hide it: issues are reported
        // separately and do not block recovery of a valid unfenced call.
        if calls.isEmpty {
            calls.append(contentsOf: parseUnfencedJSONToolCalls(from: responseText))
        }


        // Audit 2026-09-08 (Qwen live): models sometimes emit a tool call the
        // STREAM CUT OFF mid-JSON — `call {"name": "list_dir", "arguments` —
        // no fence, no closing brace. Such a response is NOT a final answer;
        // recover the tool name and keep the loop alive so the driver can
        // feed back "incomplete call, re-emit" instead of showing the stub.
        // Only when no complete call parsed — the stub detector is a fallback,
        // never a second opinion on a well-formed call.
        if calls.isEmpty && issues.isEmpty {
            calls.append(contentsOf: parseTruncatedToolCallStub(from: responseText))
        }
        // Один и тот же вызов, представленный в нескольких форматах (например,
        // DSML блок, который заодно содержит валидный JSON — оба парсера его
        // увидят), не должен исполняться дважды.
        return (deduplicated(calls), issues)
    }

    /// Убрать дубликаты вызовов: одинаковые (имя + аргументы) оставляем один раз.
    static func deduplicated(_ calls: [WebToolCall]) -> [WebToolCall] {
        var seen = Set<String>()
        var unique: [WebToolCall] = []
        for call in calls {
            let argsKey = call.arguments.keys.sorted()
                .map { "\($0)=\(call.arguments[$0] ?? "")" }
                .joined(separator: "&")
            let key = call.name + "|" + argsKey
            if seen.insert(key).inserted {
                unique.append(call)
            }
        }
        return unique
    }

    /// The tool name written inside a broken block, so the error result names
    /// the tool the model meant to call.
    static func recoveredToolName(from block: String) -> String? {
        let pattern = "\"name\"\\s*:\\s*\"([A-Za-z_][A-Za-z0-9_.-]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: block, range: NSRange(location: 0, length: (block as NSString).length)),
              match.numberOfRanges >= 2 else { return nil }
        return (block as NSString).substring(with: match.range(at: 1))
    }

    /// Detect a stream-truncated tool call: a known tool name followed by an
    /// UNTERMINATED JSON body (no closing `}` after the name, no fence). The
    /// recovered call carries whatever arguments are readable plus a marker so
    /// validation reports it as incomplete rather than executing blindly.
    /// Live (Qwen 2026-09-08): reasoning streams also die mid-XML, mangling
    /// the tags into `⟨path⟩ ⟨arg_value⟩` — a bare known-tool mention near
    /// half-written argument tags is detected the same way.
    static func parseTruncatedToolCallStub(from text: String) -> [WebToolCall] {
        // JSON form: `{"name": "tool", ...` with no closing brace.
        let pattern = "\\{\\s*\"name\"\\s*:\\s*\"([A-Za-z_][A-Za-z0-9_.-]*)\""
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let scanner = text as NSString
            var calls: [WebToolCall] = []
            for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length)) where match.numberOfRanges >= 2 {
                let name = scanner.substring(with: match.range(at: 1))
                guard let canonical = canonicalToolName(name) else { continue }
                let rest = scanner.substring(from: match.range(at: 1).location + match.range(at: 1).length)
                if rest.contains("}") { continue }
                var args = truncatedCallArguments(from: rest)
                args["__mycoder_truncated"] = "1"
                calls.append(WebToolCall(name: canonical, arguments: args))
            }
            if !calls.isEmpty { return calls }
        }
        // Mangled/truncated XML form: the tool name followed by half-written
        // argument tags (⟨arg⟩ / ⟨/arg_value⟩ / <arg without close) — the
        // complete tagged parser already handles well-formed XML.
        for (canonical, raw) in WebEmulatedTool.allCases.map({ (canonicalToolName($0.rawValue)!, $0.rawValue) }) {
            guard let range = text.range(of: raw) else { continue }
            let after = String(text[range.upperBound...])
            // A well-formed tagged body after the mention parses upstream —
            // never touch those. Vendors also mangle angle brackets into
            // unicode look-alikes, so accept both ASCII and mangled closers.
            if after.contains("</\(raw)>") || after.contains("⟩/\(raw)⟩") { continue }
            // Truncated/mangled argument region right after the tool mention:
            // half-written or unicode-mangled angle tags. A CLOSING tag of the
            // tool right after the mention (any bracket flavor) means the
            // tagged parser already handled the full body — skip.
            if after.hasPrefix(">") || after.hasPrefix("⟩") { continue }
            // A closed </tool_name> right after the mention means the NAME
            // arrived complete — but the ARGUMENT region may still be a
            // mangled truncation (live: "⟨path⟩ ⟨arg_value⟩ ." with real
            // <arg_key>/<arg_value> tags never appearing). Only skip when
            // real ASCII argument tags exist AND no mangled ones.
            if after.hasPrefix("</tool_name>") || after.hasPrefix("⟩/tool_name⟩") {
                let argRegion = String(after[after.index(after.startIndex, offsetBy: min(after.count, 13))...])
                let opensRealTag = argRegion.contains("<arg_key") || argRegion.contains("<arg_value") || argRegion.contains("<path")
                let opensMangledTag = argRegion.contains("⟨arg") || argRegion.contains("⟨path")
                if opensMangledTag {
                    var args = truncatedCallArguments(from: argRegion)
                    args["__mycoder_truncated"] = "1"
                    return [WebToolCall(name: canonical, arguments: args)]
                }
                if opensRealTag { continue }
                // Audit 2026-09-09 (test regression): a COMPLETE well-formed
                // XML body whose angle brackets the vendor mangles into ⟨…⟩
                // ("⟨pattern⟩x⟨/pattern⟩") contains argument-shaped tags but
                // no truncation — a generic "any ⟨ counts" check fired a fake
                // truncated stub and blocked the call. Only half-written
                // argument tags (⟨arg…, ⟨path…, <arg without closer, or an
                // unterminated ⟨ value) mark a real cut stream.
                let hasHalfWrittenArg = argRegion.contains("⟨arg") || argRegion.contains("⟨path")
                    || (argRegion.contains("<arg") && !argRegion.contains(">arg"))
                    || (argRegion.contains("⟨") && !argRegion.contains("⟩"))
                if hasHalfWrittenArg {
                    var args = truncatedCallArguments(from: argRegion)
                    args["__mycoder_truncated"] = "1"
                    return [WebToolCall(name: canonical, arguments: args)]
                }
                continue
            }
            if after.contains("⟨") || after.contains("<arg") || after.contains("</tool") {
                var args = truncatedCallArguments(from: after)
                args["__mycoder_truncated"] = "1"
                return [WebToolCall(name: canonical, arguments: args)]
            }
        }
        // Truncated `<tool_name>NAME` prefix (Qwen live: the stream died
        // INSIDE the tool name itself — "<tool_name>list" — leaving a known
        // tool prefix with no closing bracket at all). Recover it as a stub
        // so the driver asks the model to re-emit the complete call.
        if let nameRange = text.range(of: "<tool_name>") ?? text.range(of: "⟨tool_name⟩") {
            let candidate = String(text[nameRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            for (canonical, raw) in WebEmulatedTool.allCases.map({ (canonicalToolName($0.rawValue)!, $0.rawValue) }) {
                if candidate.hasPrefix(raw) { continue }   // full name → handled above
                if raw.hasPrefix(candidate), !candidate.isEmpty {
                    return [WebToolCall(name: canonical, arguments: ["__mycoder_truncated": "1"])]
                }
            }
        }
        return []
    }

    /// Best-effort argument extraction from a truncated JSON body: any
    /// `"key": "value` pairs, even when the closing quote/brace was lost.
    static func truncatedCallArguments(from body: String) -> [String: String] {
        var args: [String: String] = [:]
        let pattern = "\"([A-Za-z_][A-Za-z0-9_.-]*)\"\\s*:\\s*\"?([^\",}]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return args }
        let scanner = body as NSString
        for match in regex.matches(in: body, range: NSRange(location: 0, length: scanner.length)) where match.numberOfRanges >= 3 {
            if let k = substring(in: match, at: 1, of: scanner),
               let v = substring(in: match, at: 2, of: scanner) {
                let key = k.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { args[key] = v.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        return args
    }

    /// Parse the XML tool-call format that big-pickle / MiMo-style models emit:
    /// `<tool_call>execute_command<arg_key>command</arg_key><arg_value>pwd</arg_value></tool_call>`.
    /// Live models pretty-print the block across lines (newline after the name,
    /// between arg tags, and before </tool_call>), so every boundary tolerates
    /// whitespace — otherwise the calls are silently dropped and the agentic
    /// loop stalls showing raw unexecuted tool calls.
    static func parseTaggedToolCalls(from text: String) -> [WebToolCall] {
        let scanner = text as NSString
        let pattern = "<tool_call>\\s*([A-Za-z_][A-Za-z0-9_.-]*)((?:\\s*<arg_key>[\\s\\S]*?</arg_key>\\s*<arg_value>[\\s\\S]*?</arg_value>)*)\\s*</tool_call>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var calls: [WebToolCall] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length)) where match.numberOfRanges >= 3 {
            let name = scanner.substring(with: match.range(at: 1))
            guard let canonical = canonicalToolName(name) else { continue }
            let pairsBody = scanner.substring(with: match.range(at: 2))
            let argPattern = "<arg_key>([\\s\\S]*?)</arg_key>\\s*<arg_value>([\\s\\S]*?)</arg_value>"
            var args: [String: String] = [:]
            if let pairRegex = try? NSRegularExpression(pattern: argPattern) {
                let body = pairsBody as NSString
                for pm in pairRegex.matches(in: pairsBody, range: NSRange(location: 0, length: body.length)) where pm.numberOfRanges >= 3 {
                    if let k = substring(in: pm, at: 1, of: body),
                       let v = substring(in: pm, at: 2, of: body) {
                        args[k.trimmingCharacters(in: .whitespacesAndNewlines)] = v
                    }
                }
            }
            calls.append(WebToolCall(name: canonical, arguments: args))
        }
        return calls
    }

    /// Parse the SHORT XML form taught by the system preamble:
    /// `<list_dir>path=.</list_dir>`. Tag name must be a known tool (this
    /// rejects arbitrary HTML), args are `key=value` pairs separated by
    /// whitespace with optionally quoted values.
    static func parseShortTaggedCalls(from text: String) -> [WebToolCall] {
        let scanner = text as NSString
        let pattern = "<([A-Za-z_][A-Za-z0-9_.-]*)>([^<>]*)</\\1>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        var calls: [WebToolCall] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length)) where match.numberOfRanges >= 3 {
            let name = scanner.substring(with: match.range(at: 1))
            guard let canonical = canonicalToolName(name) else { continue }
            let body = scanner.substring(with: match.range(at: 2))
            calls.append(WebToolCall(name: canonical, arguments: parseShortTagArgs(body)))
        }
        return calls
    }

    /// Parse `k=v` pairs: `path=.`, `path="my dir"`, `limit=5`.
    static func parseShortTagArgs(_ text: String) -> [String: String] {
        var args: [String: String] = [:]
        let scanner = text as NSString
        let pattern = "([A-Za-z_][A-Za-z0-9_.-]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|(\\S+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return args }
        for m in regex.matches(in: text, range: NSRange(location: 0, length: scanner.length)) where m.numberOfRanges >= 6 {
            guard let key = substring(in: m, at: 1, of: scanner) else { continue }
            let value = substring(in: m, at: 3, of: scanner)
                ?? substring(in: m, at: 4, of: scanner)
                ?? substring(in: m, at: 5, of: scanner)
                ?? ""
            args[key.trimmingCharacters(in: .whitespacesAndNewlines)] = value
        }
        return args
    }

    /// Parse `[tool call: NAME with key value / key="value" ...]`.
    static func parseInformalCalls(from text: String) -> [WebToolCall] {
        let scanner = text as NSString
        let pattern = "\\[tool call:\\s*([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        var calls: [WebToolCall] = []
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        for match in matches where match.numberOfRanges >= 2 {
            let body = scanner.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = body.split(separator: " ", maxSplits: 1).map(String.init)
            guard let rawName = tokens.first, let name = canonicalToolName(rawName) else { continue }
            var argsText = tokens.count > 1 ? tokens[1] : ""
            // Drop the connective "with": "[tool call: LS with path "."]" →
            // args "path \".\"".
            let withPrefix = argsText.trimmingCharacters(in: .whitespaces)
            if withPrefix.hasPrefix("with ") {
                argsText = String(withPrefix.dropFirst(5))
            }
            calls.append(WebToolCall(name: name, arguments: parseInformalArgs(argsText)))
        }
        return calls
    }

    /// Parse `path "."` / `path="."` / `path='.'` / `path=.` / `pattern "x"`
    /// into [String: String]. Bare `key value` (space-separated, unquoted)
    /// stays unsupported — too ambiguous with paths containing spaces.
    static func parseInformalArgs(_ text: String) -> [String: String] {
        var args: [String: String] = [:]
        let scanner = text as NSString
        // k="v" OR k "v" OR k='v' OR k=v. Alternation groups: the branch
        // that did NOT match has NSNotFound ranges — guard before substring.
        let key = "([A-Za-z_][A-Za-z0-9_]*)"
        let quoted = key + "\\s*=\\s*\"([^\"]*)\""       // groups 1,2
            + "|" + key + "\\s+\"([^\"]*)\""             // groups 3,4
            + "|" + key + "\\s*=\\s*'([^']*)'"           // groups 5,6
            + "|" + key + "\\s*=\\s*(\\S+)"              // groups 7,8
        guard let regex = try? NSRegularExpression(pattern: quoted) else { return args }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        for m in matches where m.numberOfRanges >= 9 {
            if let key = substring(in: m, at: 1, of: scanner),
               let value = substring(in: m, at: 2, of: scanner) {
                args[key] = value
            } else if let key = substring(in: m, at: 3, of: scanner),
                      let value = substring(in: m, at: 4, of: scanner) {
                args[key] = value
            } else if let key = substring(in: m, at: 5, of: scanner),
                      let value = substring(in: m, at: 6, of: scanner) {
                args[key] = value
            } else if let key = substring(in: m, at: 7, of: scanner),
                      let value = substring(in: m, at: 8, of: scanner) {
                args[key] = value
            }
        }
        return args
    }

    /// Safe group extraction: returns nil for NSNotFound so the alternation
    /// branches of an NSRegularExpression never crash `substring(with:)`.
    static func substring(in match: NSTextCheckingResult, at index: Int,
                                  of scanner: NSString) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return scanner.substring(with: range)
    }
}
