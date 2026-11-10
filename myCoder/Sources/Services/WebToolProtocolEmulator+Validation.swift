import Foundation

extension WebToolProtocolEmulator {
    /// Error feedback for a ```tool block whose JSON never parsed — live
    /// 2026-10-25: the host silently dropped a malformed call, the loop treated
    /// the response as a final answer and the model apologized instead of
    /// fixing its output. The returned text goes back to the model so it can
    /// re-emit a complete block; nil when every fenced block parsed.
    static func malformedToolBlockFeedback(from responseText: String) -> String? {
        guard let malformed = malformedToolCall(from: responseText) else { return nil }
        return """
        Your previous tool call was NOT executed: \(malformed.problem). Re-emit the COMPLETE tool call block with valid arguments, then stop and wait for its result.
        """
    }

    /// Имя инструмента и причина, по которой ```tool блок не стал вызовом.
    /// Нужно, чтобы даже нераспознанный вызов попал под спойлер с причиной,
    /// а не исчез из чата молча.
    static func malformedToolCall(from responseText: String) -> (name: String, problem: String)? {
        let scanner = responseText as NSString
        let pattern = "```tool\\s*\\n(.*?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let matches = regex.matches(in: responseText, range: NSRange(location: 0, length: scanner.length))
        for match in matches where match.numberOfRanges >= 2 {
            let block = scanner.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "\u{00A0}", with: " ")
            if parseSingleCall(block) != nil { continue }
            return (recoveredToolName(from: block) ?? "tool", describeJSONProblem(block))
        }

        // DSML/Anthropic: блок вызова присутствует, но не закрыт (поток
        // оборвался) — парсер его не принял, и вызов раньше исчезал молча.
        // Это тоже «прописанный, но не исполненный» вызов.
        let normalized = responseText.replacingOccurrences(of: "\u{FF5C}", with: "|")
        if normalized.contains("DSML| invoke") || normalized.contains("DSML invoke"),
           DSMLToolCallParser.parseCalls(from: responseText).isEmpty {
            return (firstAttributeValue("name", in: normalized) ?? "tool",
                    "incomplete or unclosed DSML invoke block")
        }
        if normalized.contains("<function_calls"), !normalized.contains("</function_calls"),
           ExtraToolCallFormatParsers.parseAll(from: responseText).isEmpty {
            return ("tool", "unclosed function_calls block")
        }
        if normalized.contains("<tool_use"), !normalized.contains("</tool_use"),
           ExtraToolCallFormatParsers.parseAll(from: responseText).isEmpty {
            return ("tool", "unclosed tool_use block")
        }
        return nil
    }

    /// Первое значение атрибута `name="…"` в тексте (для имени инструмента
    /// из нераспознанного блока).
    static func firstAttributeValue(_ attribute: String, in text: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: attribute))\\s*=\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text,
                                           range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges >= 2 else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    static func describeJSONProblem(_ block: String) -> String {
        var inString = false
        var escaped = false
        var stack: [Character] = []
        for ch in block {
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": stack.append("}")
                case "[": stack.append("]")
                case "}", "]": if !stack.isEmpty { stack.removeLast() }
                default: break
                }
            }
        }
        if inString || escaped {
            return "its JSON string was not terminated (a quote was opened but never closed)"
        }
        if !stack.isEmpty {
            let plural = stack.count == 1 ? "" : "s"
            return "its JSON was unfinished (\(stack.count) closing bracket\(plural) missing)"
        }
        return "its JSON was invalid"
    }

    /// Stringify one JSON scalar arg. Live 2026-09-12: a naive "\(v)" turned
    /// every non-string into garbage — first the literal text "\(v)"
    /// (escaped backslash, offset ignored 3×), then — after unescaping —
    /// JSON `true` into "1" (NSNumber description), silently disabling
    /// staged/addAll/create. JSON booleans canonicalize to "true"/"false";
    /// numbers stringify. NOTE: this comment renders "\(v)" with a single
    /// backslash; the historical bug had two.
    static func jsonScalarString(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let num = v as? NSNumber, CFGetTypeID(num) == CFBooleanGetTypeID() {
            return num.boolValue ? "true" : "false"
        }
        return "\(v)"
    }

    /// Tolerant boolean flag for tool args from any syntax (JSON true,
    /// short-XML staged=true, informal staged=1): "true"/"1"/"yes".
    static func isTruthyFlag(_ value: String?) -> Bool {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return v == "true" || v == "1" || v == "yes"
    }

    /// Complete-but-unfenced JSON tool calls (audit 2026-09-08, Qwen live):
    /// the model writes `{"name": "list_dir", "args": {"path": "."}}` plainly
    /// in the answer (sometimes with NBSP instead of spaces, sometimes with a
    /// stray `tool\n1\n` prefix) and no ```tool fence survives the stream.
    /// Balanced-brace scan finds each object; parseSingleCall validates it.
    static func parseUnfencedJSONToolCalls(from text: String) -> [WebToolCall] {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        guard let start = normalized.range(of: "{\"name\"") else { return [] }
        var calls: [WebToolCall] = []
        var searchStart = start.lowerBound
        while let openRange = normalized.range(of: "{", range: searchStart..<normalized.endIndex) {
            guard let (object, next) = balancedJSONObject(in: normalized, from: openRange.lowerBound) else { break }
            if let call = parseSingleCall(object) {
                calls.append(call)
            }
            searchStart = next
        }
        return calls
    }

    /// Извлечь первый сбалансированный `{ … }` объект, начиная с `start`,
    /// вернуть его текст и индекс сразу после него (nil при разбалансировке).
    static func balancedJSONObject(in text: String, from start: String.Index) -> (String, String.Index)? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let ch = text[index]
            if escaped { escaped = false }
            else if ch == "\\" && inString { escaped = true }
            else if ch == "\"" { inString.toggle() }
            else if !inString {
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return (String(text[start...index]), text.index(after: index))
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// True when a response contains no tool call → the model produced a final answer.
    /// Audit 2026-09-09 (Qwen live): a vendor ERROR placeholder ("The current
    /// content is empty, please regenerate.") contains no tool call either,
    /// but it is a failed generation, never a final answer.
    static func isFinalResponse(_ responseText: String) -> Bool {
        guard !WebVendorErrorPlaceholderLogic.isErrorPlaceholder(responseText) else { return false }
        return parseToolCalls(from: responseText).isEmpty
    }

    /// Собрать результаты НЕСКОЛЬКИХ вызовов одного ответа модели в один блок:
    /// модель получает их одним сообщением, а не отдельным запросом на вызов.
    static func formatToolResults(_ results: [(name: String, result: String)]) -> String {
        results.map { formatToolResult(name: $0.name, result: $0.result) }
            .joined(separator: "\n")
    }

    /// Format a tool result to send back to the web chat as the next message
    /// (plan Блок 2 п.14).
    static func formatToolResult(name: String, result: String) -> String {
        """
        ```tool_result
        {"name": "\(name)", "result": \(jsonEncoded(result))}
        ```
        """
    }

    static func jsonEncoded(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        // Extract the inner string with quotes from ["..."] → "..."
        if let str = String(data: data, encoding: .utf8) {
            let trimmed = str.dropFirst().dropLast()   // remove [ ]
            return String(trimmed)
        }
        return "\"\(s)\""
    }

    /// Whether the agentic loop should stop (plan Блок 2 п.17): either the model
    /// gave a final answer or the iteration limit is reached.
    static func shouldStopLoop(iteration: Int, maxIterations: Int, lastResponse: String) -> Bool {
        iteration >= maxIterations || isFinalResponse(lastResponse)
    }

    /// Validate a tool call's arguments before executing (plan Блок 2 п.18):
    /// paths must stay within the project root UNLESS accessLevel allows broader access;
    /// destructive tools flagged. Returns `nil` when valid, or the specific validation error.
    ///
    /// `grantedRoots` are folders the user explicitly allowed access to after
    /// an out-of-project request — a path inside one of them is valid.
    static func validate(_ call: WebToolCall,
                         projectRoot: String,
                         accessLevel: AccessLevel = .askBeforeChanges,
                         grantedRoots: [String] = []) -> WebToolValidationError? {
        let call = canonicalized(call)
        guard WebEmulatedTool(rawValue: call.name) != nil else {
            return .unknownTool(call.name)
        }
        // Path boundary check is now permission-based, not hard restriction.
        // At .fullAccess, any path is allowed. At lower levels, restrict to project root.
        if accessLevel != .fullAccess,
           let path = call.arguments["path"],
           !OutOfProjectAccessLogic.isAccessible(
               path: path,
               projectRoot: projectRoot,
               grantedRoots: grantedRoots
           ) {
            return .pathEscapesProject(path)
        }
        return nil
    }

    /// Text returned to the model when a tool call fails validation or JSON
    /// parsing. It carries both the error and the correct call syntax for that
    /// tool (user directive 2026-10-29), so the model can retry with valid
    /// JSON instead of guessing. Unknown tools have no schema — only the error
    /// is returned.
    static func validationResultText(
        for error: WebToolValidationError,
        callName: String
    ) -> String {
        let base = "validation error: \(error)"
        guard let canonical = canonicalToolName(callName),
              let tool = WebEmulatedTool(rawValue: canonical) else {
            return base
        }
        return base + "\nCorrect call syntax:\n```tool\n\(tool.rawValue) \(tool.argumentSchema)\n```"
    }

    static func requiresApproval(_ call: WebToolCall) -> Bool {
        switch WebEmulatedTool(rawValue: canonicalized(call).name) {
        case .writeFile, .editFile, .todoWrite, .taskCreate, .taskUpdate,
             .gitBranch, .gitCheckout, .gitCommit, .gitPush, .gitPull,
             .runCommand, .task:
            return true
        default:
            return false
        }
    }

    static func isPathInsideRoot(_ path: String, root: String) -> Bool {
        let normalizedRoot = resolvedPath(root)
        let candidate: String
        if path.hasPrefix("/") {
            candidate = resolvedPath(path)
        } else {
            candidate = resolvedPath(URL(fileURLWithPath: root).appendingPathComponent(path).path)
        }
        return candidate == normalizedRoot || candidate.hasPrefix(normalizedRoot + "/")
    }

    /// Resolve symlinks so a symlink placed inside the project root cannot
    /// escape the root check and point at, e.g., /etc/passwd (audit ARCH-06).
    /// Strategy: (1) `realpath` for existing paths; (2) lexical `..`/`.`
    /// resolution + `realpath` for write-targets whose only missing component
    /// is the file itself; (3) as a last resort resolve the longest EXISTING
    /// ancestor via realpath and append the missing tail. `..` must be
    /// resolved lexically first — `URL.deletingLastPathComponent()` is a
    /// no-op on a trailing `..`, which made an earlier walk-up spin forever.
    static func resolvedPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if path.withCString({ realpath($0, &buffer) }) != nil {
            return String(cString: buffer)
        }
        let lexical = lexicallyResolved(path)
        if lexical.withCString({ realpath($0, &buffer) }) != nil {
            return String(cString: buffer)
        }
        // Split into the longest existing ancestor + missing tail.
        var components = Array(
            URL(fileURLWithPath: lexical).pathComponents.filter { $0 != "/" && !$0.isEmpty }
        )
        var missingTail: [String] = []
        var resolvedAncestor: String?
        while !components.isEmpty {
            let ancestor = "/" + components.joined(separator: "/")
            if ancestor.withCString({ realpath($0, &buffer) }) != nil {
                resolvedAncestor = String(cString: buffer)
                break
            }
            missingTail.insert(components.removeLast(), at: 0)
        }
        if let resolvedAncestor {
            let trimmed = resolvedAncestor == "/" ? "" : resolvedAncestor
            return missingTail.isEmpty ? resolvedAncestor : trimmed + "/" + missingTail.joined(separator: "/")
        }
        return lexical
    }

    /// Textual resolution of `.`/`..` without touching the filesystem.
    static func lexicallyResolved(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents
        var stack: [String] = []
        for component in components {
            switch component {
            case "..":
                if !stack.isEmpty { stack.removeLast() }
            case ".", "", "/":
                continue
            default:
                stack.append(component)
            }
        }
        return stack.isEmpty ? "/" : "/" + stack.joined(separator: "/")
    }
}
