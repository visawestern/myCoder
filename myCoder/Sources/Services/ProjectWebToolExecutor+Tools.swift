import Foundation

extension ProjectWebToolExecutor {
    // MARK: - Todo persistence (plan Раздел 12 — real tool ops, not stubs)

    func todoFileURL() -> URL {
        MyCoderPaths.todosURL(projectPath: projectRoot)
    }

    /// Read the current checklist AND the active execution plan.
    /// The plan (spec decomposition) is the authoritative checklist: the user
    /// asked for the plan to be aliased into `todo_read`, so the assistant
    /// always sees the atomic tasks, their dependencies and their criteria.
    func todoRead() -> String {
        let todos = loadTodoItems()
        let plan = PlanTodoBridge.planItems(projectPath: projectRoot)
        return PlanTodoBridge.mergedText(sessionTodos: todos, planItems: plan)
    }

    /// Raw todo items (bare array), shared by todo_read/todo_write and the
    /// granular task_create/list/update tools (Claude Code Task* parity).
    /// Corrupt or missing files read as empty — never a crash.
    func loadTodoItems() -> [[String: Any]] {
        let url = todoFileURL()
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        if let array = json as? [[String: Any]] {
            return array
        }
        if let dict = json as? [String: Any],
           let array = dict["todos"] as? [[String: Any]] {
            return array
        }
        return []
    }

    /// Пример корректного JSON для `todo_write`. Подставляется в сообщения об
    /// ошибках (U6), чтобы модель могла сразу исправить запрос.
    /// Вход: нет. Выход: строка-пример без перевода строки. Зависимости: нет.
    private static let todoWriteExample =
        "[{\"id\": \"1\", \"content\": \"сделать X\", \"status\": \"pending\"}]"

    /// Replace the todo list with the provided JSON array and persist it.
    /// Вход: `todosJson` — строка JSON (массив или {"todos": [...]}).
    /// Выход: "ok" или сообщение об ошибке с примером форматирования.
    /// Зависимости: `todoFileURL`, `JSONSerialization`, `saveTodoItems`.
    func todoWrite(todosJson: String) -> String {
        guard let data = todosJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return "error: invalid JSON — expected a JSON array of todo objects, например:\n"
                + Self.todoWriteExample
        }
        // Accept both a bare array and {"todos": [...]} wrapper.
        let todos: [[String: Any]]
        if let array = json as? [[String: Any]] {
            todos = array
        } else if let dict = json as? [String: Any],
                  let array = dict["todos"] as? [[String: Any]] {
            todos = array
        } else {
            return "error: expected a JSON array or {\"todos\": [...]} object, например:\n"
                + Self.todoWriteExample
        }
        // Validate each todo has required fields.
        for item in todos {
            guard let id = item["id"] as? String, !id.isEmpty,
                  let content = item["content"] as? String, !content.isEmpty else {
                return "error: each todo must have non-empty 'id' and 'content' strings"
            }
        }
        return saveTodoItems(todos, operation: "todo_write")
    }

    /// Persist validated todo items (bare array) through undo + history.
    /// Shared by todo_write and the granular task_* tools.
    func saveTodoItems(_ todos: [[String: Any]], operation: String) -> String {
        let url = todoFileURL()
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let outData = try JSONSerialization.data(withJSONObject: todos, options: [.prettyPrinted, .sortedKeys])
            try performFileOperation(operation: operation, fileURL: url) {
                try outData.write(to: url)
            }
            return "ok: saved \(todos.count) todo\(todos.count == 1 ? "" : "s")"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    // MARK: - Granular task tools (Claude Code TaskCreate/List/Update parity)

    /// Valid task statuses. Common model spellings are normalized.
    static func normalizedTaskStatus(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "pending", "todo", "open", "new":
            return "pending"
        case "in_progress", "in-progress", "inprogress", "active", "doing", "started":
            return "in_progress"
        case "completed", "complete", "done", "finished", "closed":
            return "completed"
        default:
            return nil
        }
    }

    func taskCreate(content: String, status: String?) -> String {
        let resolved: String
        if let s = status, !s.isEmpty {
            guard let normalized = Self.normalizedTaskStatus(s) else {
                return "error: unknown status '\(s)' (use pending, in_progress, or completed)"
            }
            resolved = normalized
        } else {
            resolved = "pending"
        }
        var todos = loadTodoItems()
        let id = UUID().uuidString.prefix(8).lowercased()
        todos.append(["id": String(id), "content": content, "status": resolved])
        let result = saveTodoItems(todos, operation: "task_create")
        guard result.hasPrefix("ok") else { return result }
        return "ok: created task \(id) [\(resolved)]: \(content)"
    }

    func taskUpdate(id: String, content: String?, status: String?) -> String {
        var todos = loadTodoItems()
        guard let idx = todos.firstIndex(where: { ($0["id"] as? String) == id }) else {
            // The id may address a task of the execution plan (the plan is
            // aliased into the todo tools) — move that one instead.
            if let planResult = updatePlanItem(id: id, status: status) {
                return planResult
            }
            return "error: no task with id '\(id)' — use task_list or todo_read to see ids"
        }
        if let content, !content.isEmpty {
            todos[idx]["content"] = content
        }
        if let s = status, !s.isEmpty {
            guard let normalized = Self.normalizedTaskStatus(s) else {
                return "error: unknown status '\(s)' (use pending, in_progress, or completed)"
            }
            todos[idx]["status"] = normalized
        }
        let result = saveTodoItems(todos, operation: "task_update")
        guard result.hasPrefix("ok") else { return result }
        let item = todos[idx]
        return "ok: updated task \(id) [\((item["status"] as? String) ?? "pending")]: \((item["content"] as? String) ?? "")"
    }

    /// Move a task of the execution plan (status only — the plan's text is
    /// owned by the planner). Returns nil when the id is not a plan task.
    func updatePlanItem(id: String, status: String?) -> String? {
        guard let status, !status.isEmpty else { return nil }
        guard let database = try? ProjectDatabaseManager.manager(forProjectPath: projectRoot) else {
            return nil
        }
        let store = database.makeSpecStore()
        let projectID = ProjectIdentityLogic.projectID(for: projectRoot)
        guard let revision = try? store.latestRevision(projectID: projectID) else { return nil }
        let nodes = (try? store.nodes(revisionID: revision.id)) ?? []
        guard let node = nodes.first(where: { $0.externalKey == id }) else { return nil }
        let planStatus = Self.planStatus(for: status)
        // The plan runs one task at a time: only the next runnable task may
        // be started (same rule the spec wizard enforces).
        if planStatus == "running" {
            let edges = (try? store.edges(revisionID: revision.id)) ?? []
            let next = SpecNodeExecutionLogic.nextRunnableNode(nodes: nodes, edges: edges)
            guard next?.id == node.id else {
                let nextKey = next?.externalKey ?? "none"
                return "error: task \(id) is not the next runnable task (next: \(nextKey)) — finish or skip the current task first"
            }
        }
        guard (try? store.updateNodeStatus(nodeID: node.id, status: planStatus, updatedAt: Int64(Date().timeIntervalSince1970))) == true else {
            return "error: could not update plan task \(id)"
        }
        return "ok: updated plan task \(id) [\(planStatus)]: \(node.title)"
    }

    /// Todo status vocabulary → plan status vocabulary.
    static func planStatus(for status: String) -> String {
        switch status.lowercased() {
        case "completed", "complete", "done":
            return "done"
        case "in_progress", "in-progress", "inprogress", "active":
            return "running"
        default:
            return "pending"
        }
    }

    // MARK: - Installed skill lookup (Claude Code Skill parity)

    /// List installed skill ids. Real filesystem read, never a stub.
    func skillList() -> String {
        let dir = MyCoderPaths.skillsDir(homeDirectory: homeDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return "no installed skills (add them under ~/.mycoder/skills/<id>/SKILL.md)"
        }
        let ids = entries.filter { $0.hasDirectoryPath }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0 != "registry" }
            .sorted()
        guard !ids.isEmpty else {
            return "no installed skills (add them under ~/.mycoder/skills/<id>/SKILL.md)"
        }
        return "installed skills:\n" + ids.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Return an installed skill's SKILL.md (bounded). Unknown names fail
    /// honestly with the installed list instead of hallucinating content.
    func skillRead(name: String) -> String {
        let dir = MyCoderPaths.skillsDir(homeDirectory: homeDirectory)
            .appendingPathComponent(name, isDirectory: true)
        let file = dir.appendingPathComponent("SKILL.md")
        guard let content = try? String(contentsOf: file, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "error: no installed skill named '\(name)'. \(skillList())"
        }
        return Self.boundedSkillText(content, name: name)
    }

    static func boundedSkillText(_ content: String, name: String, charCap: Int = 12000) -> String {
        guard content.count > charCap else { return content }
        return String(content.prefix(charCap))
            + "\n\n[truncated: skill '\(name)' exceeds \(charCap) chars, first \(charCap) shown]"
    }

    // MARK: - Web fetch (Claude Code WebFetch parity)

    /// Fetch a page as bounded plain text. http/https only; localhost allowed
    /// (the tool runs on the user's own machine under their approval policy).
    func fetchWebPage(urlString: String, limit: Int? = nil,
                      session: URLSession = .shared) async -> String {
        guard let url = Self.validatedFetchURL(urlString) else {
            return "error: invalid URL '\(urlString)' (http/https only)"
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("myCoder/1.0 (tool web_fetch)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,text/plain,*/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "error: no HTTP response from \(urlString)"
            }
            guard (200..<300).contains(http.statusCode) else {
                return "error: HTTP \(http.statusCode) from \(urlString)"
            }
            guard let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                return "error: undecodable response body from \(urlString)"
            }
            let text = Self.stripHTMLToText(html)
            guard !text.isEmpty else {
                return "error: no readable text at \(urlString)"
            }
            return Self.truncateFetch(text, limit: limit)
        } catch {
            return "error: fetch failed for \(urlString): \(error.localizedDescription)"
        }
    }

    /// Advanced browser fetch through the AntiBrowser REST engine: navigate,
    /// optionally click a selector, then read (page text | selector text |
    /// JS expression) and optionally return a screenshot. Pure parts
    /// (planning/rendering) live in BrowserFetchTool.swift and are tested
    /// by BrowserFetchToolTests.
    func fetchBrowserPage(arguments: [String: String]) async -> String {
        switch BrowserFetchPlanner.parse(arguments) {
        case .failure(let err):
            return err.message
        case .success(let plan):
            guard let bridge else {
                return "error: browser_fetch requires an active browser session (bridge not available)"
            }
            do {
                try await bridge.navigate(to: plan.url)
                if let selector = plan.clickSelector {
                    try await bridge.click(selector: selector)
                }
                var mainText = ""
                var scriptResult: Any? = nil
                var didEvaluateScript = false
                if let script = plan.script {
                    scriptResult = try await bridge.evaluateJS(script)
                    didEvaluateScript = true
                } else if let selector = plan.readSelector {
                    mainText = try await bridge.readText(selector: selector)
                } else {
                    mainText = try await bridge.pageText()
                }
                var png: Data? = nil
                if plan.screenshot {
                    png = try? await bridge.screenshot(selector: nil)
                }
                return BrowserFetchRendering.render(
                    text: mainText,
                    scriptResult: scriptResult,
                    includeScript: didEvaluateScript,
                    screenshotPNG: png,
                    limit: plan.limit
                )
            } catch {
                return "error: browser_fetch failed for \(plan.url): \(error.localizedDescription)"
            }
        }
    }

    /// http/https URLs only — no file:, ftp:, data:, javascript: schemes.
    static func validatedFetchURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return nil
        }
        return url
    }

    /// Strip scripts/styles/tags to readable text. Pure and unit-tested;
    /// intentionally simple (block tags → newlines, entities decoded).
    static func stripHTMLToText(_ html: String) -> String {
        var text = html
        for pattern in ["(?s)<script.*?</script>",
                        "(?s)<style.*?</style>",
                        "(?s)<!--.*?-->",
                        "(?s)<noscript.*?</noscript>"] {
            if let regex = try? NSRegularExpression(pattern: pattern,
                                                    options: [.caseInsensitive]) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " ")
            }
        }
        text = text.replacingOccurrences(of: "(?i)<\\s*br\\s*/?\\s*>",
                                         with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</\\s*(p|div|h[1-6]|li|tr|section|article|header|footer|blockquote)\\s*>",
                                         with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    static func truncateFetch(_ text: String, limit: Int?) -> String {
        let cap = max(0, limit ?? 8000)
        guard text.count > cap else { return text }
        return String(text.prefix(cap))
            + "\n\n[truncated: page exceeds \(cap) chars, first \(cap) shown. Re-fetch with a larger limit to read more.]"
    }

    /// Grep a single file (path pointed at a file, not a directory).
    /// Same `path:line: text` hit format as the directory scan.
    func grepFile(pattern: String, displayPath: String, fileURL: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "error: bad regex" }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return "error: cannot read \(displayPath)"
        }
        let hitLimit = 100
        var hits: [String] = []
        for (i, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let s = String(line)
            if regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil {
                if hits.count >= hitLimit {
                    hits.append("⚠️ Truncated: showing first \(hitLimit) matches")
                    break
                }
                hits.append("\(displayPath):\(i + 1): \(s.trimmingCharacters(in: .whitespaces))")
            }
        }
        return hits.isEmpty ? "(no matches)" : hits.joined(separator: "\n")
    }

    func grep(pattern: String, in dir: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "error: bad regex" }
        var hits: [String] = []
        let scanned = ProjectFileScanner.scan(root: dir.path)
        let fileLimit = 500
        let hitLimit = 100
        var filesScanned = 0
        var truncatedFiles = false
        var truncatedHits = false

        scanLoop: for rec in scanned {
            if filesScanned >= fileLimit { truncatedFiles = true; break }
            filesScanned += 1
            let fileURL = dir.appendingPathComponent(rec.path)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for (i, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let s = String(line)
                if regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil {
                    // Round 29 R2: stop BEFORE exceeding the hit limit and warn,
                    // instead of silently returning a bare 100-line prefix.
                    if hits.count >= hitLimit { truncatedHits = true; break scanLoop }
                    hits.append("\(rec.path):\(i + 1): \(s.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        if hits.isEmpty {
            // Quality pass R29b: a bare "(no matches)" over a truncated scan
            // would hide the fact that files beyond the cap were never read.
            if truncatedFiles {
                return "(no matches)\n⚠️ Truncated: scanned \(fileLimit) of \(scanned.count) files"
            }
            return "(no matches)"
        }
        var result = hits.joined(separator: "\n")
        if truncatedFiles {
            result += "\n⚠️ Truncated: scanned \(fileLimit) of \(scanned.count) files"
        }
        if truncatedHits {
            result += "\n⚠️ Truncated: showing first \(hitLimit) matches"
        }
        return result
    }

    func glob(pattern: String, in dir: URL) -> String {
        guard let regexPattern = Self.globToRegexPattern(pattern),
              let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return "error: invalid glob pattern"
        }
        // Standardize first: a scan root of "." produces a "/./"-suffixed
        // path, and on macOS the enumerator yields entries under the resolved
        // symlink target (/var → /private/var). Resolve BOTH sides so the
        // prefix comparison below cannot silently drop every entry.
        let stdDir = dir.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = stdDir.path
        let enumerator = fileManager.enumerator(at: stdDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var matches: [String] = []
        var truncated = false
        let matchLimit = 500
        while let fileURL = enumerator?.nextObject() as? URL {
            // Round 29 R3: patterns are matched against the path relative to the
            // scan root (glob semantics), so `src/*.swift` and `**/*.swift`
            // work; previously only lastPathComponent was tested and every
            // pattern containing "/" answered "(no matches)".
            let fullPath = fileURL.resolvingSymlinksInPath().path
            guard fullPath.hasPrefix(rootPath + "/") else { continue }
            let relPath = String(fullPath.dropFirst(rootPath.count + 1))
            let range = NSRange(relPath.startIndex..., in: relPath)
            if regex.firstMatch(in: relPath, range: range) != nil {
                if matches.count >= matchLimit { truncated = true; break }
                matches.append(relPath)
            }
        }
        if matches.isEmpty { return "(no matches)" }
        var result = matches.sorted().joined(separator: "\n")
        if truncated {
            result += "\n⚠️ Truncated: showing first \(matchLimit) entries"
        }
        return result
    }

    /// Converts a glob pattern into an anchored regular expression string.
    /// `*` matches within one path segment (`[^/]*`), `**` spans segments
    /// (`.*/?`-style, consuming an adjacent `/`), `?` is `[^/]`, `[...]`
    /// classes pass through with glob's `!` negation translated to `^`, and
    /// everything else — including `/` and regex metacharacters — is escaped
    /// literally. Returns nil for invalid patterns (unterminated class).
    static func globToRegexPattern(_ pattern: String) -> String? {
        guard !pattern.isEmpty else { return nil }
        var out = "^"
        let chars = Array(pattern)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    out += ".*"
                    i += 2
                    if i < chars.count && chars[i] == "/" { i += 1 }
                } else {
                    out += "[^/]*"
                    i += 1
                }
            case "?":
                out += "[^/]"
                i += 1
            case "[":
                var j = i + 1
                if j < chars.count && chars[j] == "!" { j += 1 }
                if j < chars.count && chars[j] == "]" { j += 1 }
                while j < chars.count && chars[j] != "]" { j += 1 }
                guard j < chars.count else { return nil }
                var cls = String(chars[(i + 1)..<j])
                if cls.hasPrefix("!") { cls = "^" + cls.dropFirst() }
                out += "[" + cls + "]"
                i = j + 1
            case "]":
                return nil
            default:
                if ".()+^$|{}\\".contains(c) { out += "\\" }
                out.append(c)
                i += 1
            }
        }
        return out + "$"
    }

    /// Message fed back to the model when the access gate blocks a tool.
    /// Includes the tool name and the level that is required, so the model can
    /// report the limitation honestly instead of silently skipping work.
    /// Live 2026-09-12 (last chat): a blocked `run_command` ended the task in
    /// a dead-end — the model had no read-only alternative to fall back on.
    /// The message now names the concrete fallback so the model can continue
    /// instead of stalling.
    ///
    /// Input: the blocked call. Output: model-facing refusal text.
    /// Dependencies: `WebToolAccessGate` (project boundary) and `accessLevel`.
    func approvalMessage(for call: WebToolCall) -> String {
        if let path = WebToolAccessGate.outOfProjectPath(for: call, projectRoot: projectRoot) {
            return "\(call.name) requires approval to access \(path), which is outside the project folder \(projectRoot); not executed. Ask the user to allow that folder, or work inside \(projectRoot)."
        }
        let base = "\(call.name) requires approval (AccessLevel: \(accessLevel.rawValue)); not executed"
        guard WebEmulatedTool(rawValue: call.name) == .runCommand else { return base }
        return base + ". Read-only commands (cat, grep, head, tail, sed print, git log/diff/status, ls, wc) run WITHOUT approval — re-issue one of those instead, or page files with read_file offset/limit."
    }
}
