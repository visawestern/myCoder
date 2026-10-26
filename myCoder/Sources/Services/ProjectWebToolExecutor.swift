import Foundation

/// Real WebToolExecutor that runs the emulated tools against the current
/// project directory (plan Раздел 12 Блок 2 п.16). Used when a web model asks
/// for a tool via the emulated protocol. Path-safety is enforced by the driver
/// (validate) before execution; this executor still resolves inside the root.
/// When an `undoManager` is provided (normal production use), file-modifying
/// tools snapshot + record undo entries and append `request_history` rows, so
/// real tool operations feed the project's undo stack (Раздел 7 п.12-14).
/// `accessLevel` enforces the gate (Раздел 12 п.18): mutating tools follow the
/// edit policy, `run_command` only ever executes at `.fullAccess` and runs as a
/// real bounded shell process against the project directory.
struct ProjectWebToolExecutor: WebToolExecutor {
    let projectRoot: String
    let fileManager: FileManager
    let undoManager: ProjectUndoManager?
    let sessionId: String?
    let accessLevel: AccessLevel
    /// Home directory for user-global reads (installed skills). Defaults to
    /// the real home; injectable so skill tests use a temp sandbox.
    let homeDirectory: URL
    var bridge: WKWebViewBrowserBridge?
    var selectors: WebVendorSelectors?

    init(projectRoot: String,
         fileManager: FileManager = .default,
         undoManager: ProjectUndoManager? = nil,
         sessionId: String? = nil,
         accessLevel: AccessLevel = .askBeforeChanges,
         homeDirectory: URL? = nil) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
        self.undoManager = undoManager
        self.sessionId = sessionId
        self.accessLevel = accessLevel
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    func execute(_ call: WebToolCall) async -> String {
        // The access gate runs before any side effect: a gated tool is never
        // executed, it is reported back to the model as needing approval.
        // NOTE: when the driver already collected an Allow verdict it calls
        // execute(_:userApproved:) — this gate must not fire twice (F4).
        if WebToolAccessGate.permission(for: call, accessLevel: accessLevel) == .requireApproval {
            return approvalMessage(for: call)
        }
        return await run(call)
    }

    func execute(_ call: WebToolCall, userApproved: Bool) async -> String {
        if userApproved { return await run(call) }
        return await execute(call)
    }

    /// Resolve a tool path against the project root.
    ///
    /// An absolute path is used as it is: `appendingPathComponent` would glue
    /// it onto the root and produce a path that does not exist, so every
    /// absolute path outside the project resolved to a missing file.
    private func url(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: projectRoot).appendingPathComponent(path)
    }

    /// The actual tool dispatch without the approval gate (the gate lives in
    /// execute(_:) / the driver's approval-box flow, never here).
    private func run(_ call: WebToolCall) async -> String {
        // Resolve model-specific spellings ("Bash", "git-commit", ...) to the
        // canonical tool AND normalize argument names ("file_path" → "path")
        // BEFORE dispatch, so every wire format executes identically.
        guard let tool = WebEmulatedTool(rawValue: WebToolProtocolEmulator.canonicalToolName(call.name) ?? call.name) else {
            return "error: unknown tool \(call.name)"
        }
        let call = WebToolCall(
            name: tool.rawValue,
            arguments: WebToolProtocolEmulator.normalizedArguments(for: tool, from: call.arguments)
        )
        switch tool {
        case .readFile:
            guard let path = call.arguments["path"] else { return "error: missing path" }
            let url = url(for: path)
            // Image files are NOT text-readable, but web models DO support
            // vision. Instead of the old lying "this model does not support
            // image input", return a typed marker the web driver recognizes
            // and attaches the image to the NEXT chat message so the model
            // actually sees it (audit: false-negative UX bug).
            let ext = url.pathExtension.lowercased()
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff"]
            if imageExtensions.contains(ext) {
                guard let data = try? Data(contentsOf: url) else {
                    return "error: cannot read \(path)"
                }
                let bounded = data.prefix(8 * 1024 * 1024) // 8 MB safety cap
                let base64 = bounded.base64EncodedString()
                let mime = Self.imageMIME(forExtension: ext)
                return "ATTACHED_IMAGE:\(mime):\(base64)"
            }
            // Claude Code Read parity (live 2026-09-12: the model asked for
            // offset 3× and always got the file head — offset/limit were
            // neither parsed nor honored). 'offset' is the 1-based first
            // line, 'limit' the max line count; absent → legacy whole-file
            // read so existing behavior is untouched.
            let windowed = call.arguments["offset"] != nil || call.arguments["limit"] != nil
            let offset = call.arguments["offset"].flatMap { Int($0.filter(\.isNumber)) } ?? 1
            let limit = call.arguments["limit"].flatMap { Int($0.filter(\.isNumber)) }
            if ext == "svg" {
                // SVG is text — read it as text.
                guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                    return "error: cannot read \(path)"
                }
                if windowed { return Self.windowedRead(content, path: path, offset: offset, limit: limit) }
                return Self.webBoundedRead(content, path: path)
            }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                return "error: cannot read \(path)"
            }
            if windowed { return Self.windowedRead(content, path: path, offset: offset, limit: limit) }
            return Self.webBoundedRead(content, path: path)
        case .writeFile:
            guard let path = call.arguments["path"], let content = call.arguments["content"] else {
                return "error: missing path/content"
            }
            let url = url(for: path)
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try performFileOperation(operation: "write_file", fileURL: url, execute: {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                })
                return "ok: wrote \(content.count) chars to \(path)"
            } catch { return "error: \(error.localizedDescription)" }
        case .editFile:
            guard let path = call.arguments["path"],
                  let oldStr = call.arguments["old"], let newStr = call.arguments["new"] else {
                return "error: missing path/old/new"
            }
            let url = url(for: path)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                return "error: cannot read \(path)"
            }
            guard content.contains(oldStr) else { return "error: 'old' text not found in \(path)" }
            let updated = content.replacingOccurrences(of: oldStr, with: newStr)
            do {
                try performFileOperation(operation: "edit_file", fileURL: url, execute: {
                    try updated.write(to: url, atomically: true, encoding: .utf8)
                })
                return "ok: edited \(path)"
            } catch { return "error: \(error.localizedDescription)" }
        case .listDir:
            let path = call.arguments["path"] ?? "."
            let url = url(for: path)
            guard let entries = try? fileManager.contentsOfDirectory(atPath: url.path) else {
                return "error: cannot list \(path)"
            }
            return entries.sorted().joined(separator: "\n")
        case .grep:
            guard let pattern = call.arguments["pattern"] else { return "error: missing pattern" }
            let path = call.arguments["path"] ?? "."
            let target = url(for: path)
            // Claude Code parity (live 2026-09-12): 'path' may be a FILE —
            // the model passed TZ-Bezdna-v3.md and got "(no matches)"
            // because a file scanned as a directory yields zero files.
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: target.path, isDirectory: &isDir), !isDir.boolValue {
                return grepFile(pattern: pattern, displayPath: path, fileURL: target)
            }
            return grep(pattern: pattern, in: target)
        case .runCommand:
            // E12: at .fullAccess the command actually runs — a bounded real
            // shell process rooted at the project directory, returning stdout +
            // stderr + exit code. At any lower level the gate above already
            // returned the approval message and nothing executed.
            let cmd = call.arguments["command"] ?? ""
            return ProjectShellRunner.run(command: cmd, workingDirectory: projectRoot).output
        // Git operations
        case .gitStatus:
            return ProjectShellRunner.run(command: "git status", workingDirectory: projectRoot).output
        case .gitDiff:
            let staged = WebToolProtocolEmulator.isTruthyFlag(call.arguments["staged"])
            let cmd = staged ? "git diff --cached" : "git diff"
            return ProjectShellRunner.run(command: cmd, workingDirectory: projectRoot).output
        case .gitLog:
            let limit = call.arguments["limit"] ?? "10"
            return ProjectShellRunner.run(command: Self.gitLogCommand(limit: limit), workingDirectory: projectRoot).output
        case .gitBranch:
            return ProjectShellRunner.run(
                command: Self.gitBranchCommand(branch: call.arguments["branch"], create: WebToolProtocolEmulator.isTruthyFlag(call.arguments["create"])),
                workingDirectory: projectRoot).output
        case .gitCheckout:
            guard let branch = call.arguments["branch"] else { return "error: missing branch" }
            return ProjectShellRunner.run(command: Self.gitCheckoutCommand(branch: branch), workingDirectory: projectRoot).output
        case .gitCommit:
            guard let message = call.arguments["message"] else { return "error: missing message" }
            let addAll = WebToolProtocolEmulator.isTruthyFlag(call.arguments["addAll"])
            return ProjectShellRunner.run(command: Self.gitCommitCommand(message: message, addAll: addAll), workingDirectory: projectRoot).output
        case .gitPush:
            let remote = call.arguments["remote"] ?? "origin"
            let branch = call.arguments["branch"] ?? ""
            return ProjectShellRunner.run(command: Self.gitRemoteRefCommand("git push", remote: remote, branch: branch), workingDirectory: projectRoot).output
        case .gitPull:
            let remote = call.arguments["remote"] ?? "origin"
            let branch = call.arguments["branch"] ?? ""
            return ProjectShellRunner.run(command: Self.gitRemoteRefCommand("git pull", remote: remote, branch: branch), workingDirectory: projectRoot).output
        // File search & glob
        case .glob:
            let pattern = call.arguments["pattern"] ?? "*"
            let path = call.arguments["path"] ?? "."
            return glob(pattern: pattern, in: url(for: path))
        case .todoRead:
            return todoRead()
        case .todoWrite:
            guard let todosJson = call.arguments["todos"] else {
                return "error: missing 'todos' argument (expected JSON array)"
            }
            return todoWrite(todosJson: todosJson)
        case .task:
            // Sub-agent task tool - launch async sub-agent
            return await executeTask(call: call)
        case .webFetch:
            guard let url = call.arguments["url"], !url.isEmpty else {
                return "error: missing url (http/https only)"
            }
            let limit = call.arguments["limit"].flatMap { Int($0.filter(\.isNumber)) }
            return await fetchWebPage(urlString: url, limit: limit)
        case .skill:
            if let name = call.arguments["name"], !name.isEmpty {
                return skillRead(name: name)
            }
            return skillList()
        case .taskCreate:
            guard let content = call.arguments["content"], !content.isEmpty else {
                return "error: missing content"
            }
            return taskCreate(content: content, status: call.arguments["status"])
        case .taskList:
            return todoRead()
        case .taskUpdate:
            guard let id = call.arguments["id"], !id.isEmpty else {
                return "error: missing id"
            }
            return taskUpdate(id: id, content: call.arguments["content"], status: call.arguments["status"])
        }
    }

    /// Message fed back to the model when the access gate blocks a tool.
    /// Includes the tool name and the level that is required, so the model can
    /// report the limitation honestly instead of silently skipping work.
    /// Live 2026-09-12 (last chat): a blocked `run_command` ended the task in
    /// a dead-end — the model had no read-only alternative to fall back on.
    /// The message now names the concrete fallback so the model can continue
    /// instead of stalling.
    private func approvalMessage(for call: WebToolCall) -> String {
        let base = "\(call.name) requires approval (AccessLevel: \(accessLevel.rawValue)); not executed"
        guard WebEmulatedTool(rawValue: call.name) == .runCommand else { return base }
        return base + ". Read-only commands (cat, grep, head, tail, sed print, git log/diff/status, ls, wc) run WITHOUT approval — re-issue one of those instead, or page files with read_file offset/limit."
    }

    // MARK: - Shell-safe git command construction (Round 29 R1)
    //
    // Model-supplied git arguments used to be interpolated raw into a
    // `/bin/zsh -c <command>` invocation, so a crafted commit message like
    // `x" && touch pwned && echo "` escaped the surrounding quotes and ran
    // arbitrary shell beyond what the approved operation implies. Every
    // interpolated value now goes through `shellQuoted`, and numeric options
    // through `sanitizedNumber`.

    /// Wraps a value in single quotes so `$()`, backticks, `&&`, `;`, `|`,
    /// `>`, globs and whitespace lose their shell meaning. A literal `'`
    /// becomes the standard `'\''` escape sequence.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Digits-only sanitizer for numeric CLI options; falls back when the
    /// value contains no usable positive number. Bounded so a huge number
    /// cannot turn into an unbounded git query.
    static func sanitizedNumber(_ raw: String, fallback: Int, maxValue: Int = 10_000) -> Int {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty, let n = Int(digits), n > 0 else { return fallback }
        return min(n, maxValue)
    }

    static func gitLogCommand(limit: String) -> String {
        "git log --oneline -\(sanitizedNumber(limit, fallback: 10))"
    }

    static func gitBranchCommand(branch: String?, create: Bool) -> String {
        if let branch, create {
            return "git checkout -b \(shellQuoted(branch))"
        }
        return "git branch"
    }

    static func gitCheckoutCommand(branch: String) -> String {
        "git checkout \(shellQuoted(branch))"
    }

    static func gitCommitCommand(message: String, addAll: Bool) -> String {
        let addPart = addAll ? "git add -A && " : ""
        return "\(addPart)git commit -m \(shellQuoted(message))"
    }

    static func gitRemoteRefCommand(_ verb: String, remote: String, branch: String) -> String {
        // Round 29 regression restored 2026-09-06: remote/branch come from
        // MODEL-EMITTED tool arguments; an unquoted value executes arbitrary
        // shell (`remote: "origin; evil"`). Both parts are shell-quoted.
        let branchPart = branch.isEmpty ? "" : " \(shellQuoted(branch))"
        return "\(verb) \(shellQuoted(remote))\(branchPart)"
    }

    /// MIME type for an image file extension (used by the ATTACHED_IMAGE
    /// protocol between readFile and the web driver).
    static func imageMIME(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        default: return "image/png"
        }
    }

    /// Parse an ATTACHED_IMAGE result produced by `readFile` on an image.
    /// Returns (mime, raw bytes) when the string is a well-formed marker.
    static func parseAttachedImage(from result: String) -> (mime: String, data: Data)? {
        guard result.hasPrefix("ATTACHED_IMAGE:") else { return nil }
        let remainder = String(result.dropFirst("ATTACHED_IMAGE:".count))
        let parts = remainder.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              let data = Data(base64Encoded: String(parts[1])) else { return nil }
        return (String(parts[0]), data)
    }

    /// Runs a file-modifying tool under the project's undo manager when one is
    /// configured: snapshot the pre-change state, execute, record the undo
    /// entry and a `request_history` row. Without an undo manager (tests / no
    /// open project) the plain write runs unchanged.
    private func performFileOperation(operation: String, fileURL: URL, execute: () throws -> Void) throws {
        guard let undoManager, let sessionId else {
            try execute()
            return
        }
        try undoManager.executeWithUndo(operation: operation, filePath: fileURL.path, sessionId: sessionId, execute: execute)
        try undoManager.db.recordRequestHistory(
            sessionId: sessionId,
            type: "file_edit",
            payload: "{\"path\":\"\(fileURL.path)\",\"operation\":\"\(operation)\"}"
        )
    }

    // MARK: - Todo persistence (plan Раздел 12 — real tool ops, not stubs)

    private func todoFileURL() -> URL {
        MyCoderPaths.todosURL(projectPath: projectRoot)
    }

    /// Read the current todo list from `<project>/.mycoder/todos.json`.
    private func todoRead() -> String {
        let todos = loadTodoItems()
        guard !todos.isEmpty else { return "[]" }
        var lines: [String] = []
        for item in todos {
            let id = item["id"] as? String ?? "?"
            let content = item["content"] as? String ?? ""
            let status = item["status"] as? String ?? "pending"
            lines.append("[\(status)] \(id): \(content)")
        }
        return lines.joined(separator: "\n")
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

    /// Replace the todo list with the provided JSON array and persist it.
    private func todoWrite(todosJson: String) -> String {
        guard let data = todosJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return "error: invalid JSON — expected a JSON array of todo objects"
        }
        // Accept both a bare array and {"todos": [...]} wrapper.
        let todos: [[String: Any]]
        if let array = json as? [[String: Any]] {
            todos = array
        } else if let dict = json as? [String: Any],
                  let array = dict["todos"] as? [[String: Any]] {
            todos = array
        } else {
            return "error: expected a JSON array or {\"todos\": [...]} object"
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
    private func saveTodoItems(_ todos: [[String: Any]], operation: String) -> String {
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

    private func taskCreate(content: String, status: String?) -> String {
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

    private func taskUpdate(id: String, content: String?, status: String?) -> String {
        var todos = loadTodoItems()
        guard let idx = todos.firstIndex(where: { ($0["id"] as? String) == id }) else {
            return "error: no task with id '\(id)' — use task_list to see ids"
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
    private func grepFile(pattern: String, displayPath: String, fileURL: URL) -> String {
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

    private func grep(pattern: String, in dir: URL) -> String {
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

    private func glob(pattern: String, in dir: URL) -> String {
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

    /// Injected by the chat panel for API-backed routes: launches the task as
    /// a real sub-agent chat (child session in the database, listed in the
    /// right panel). nil keeps the legacy browser-session path.
    var subagentLauncher: ((String, String) async -> String)?

    private func executeTask(call: WebToolCall) async -> String {
        guard let description = call.arguments["description"],
              let prompt = call.arguments["prompt"] else {
            return "error: missing description or prompt"
        }
        if let subagentLauncher {
            return await subagentLauncher(description, prompt)
        }
        // Bridge is injected by the chat panel; without it we cannot drive a
        // browser. Surface the limitation as a catchable error rather than
        // force-unwrapping (which SIGILLed the process, pre-fix).
        guard let bridge else {
            return "error: sub-agent requires an active browser session (bridge not available)"
        }

        var config = WebProviderConfig(vendor: .kimi, toolCallDelayMs: 800, acknowledgedToS: true)
        config.selectedModel = "k2"
        let selectors = WebVendorSelectors(
            input: "textarea, div[contenteditable='true']",
            sendButton: "button[type='submit'], button[aria-label*='end'], button[data-testid='send-button']",
            responseContainer: "div[data-message-author-role='assistant'], div[class*='markdown'], div[class*='message']",
            stopButton: "button[aria-label*='top'], button[data-testid='stop-button'], button[class*='stop']"
        )

        let driver = WebChatDriver(bridge: bridge, executor: self, selectors: selectors, config: config, projectRoot: projectRoot, accessLevel: accessLevel)

        let fullPrompt = """
            \(prompt)

            You are a sub-agent working on a specific task. Your task description:
            \(description)

            Work autonomously and return a comprehensive result when done.
            """

        var result = ""
        await driver.runTurn(userMessage: fullPrompt, isFirstMessage: true) { event in
            switch event {
            case .final(let text):
                result = text
            case .error(let err):
                result = "error: \(err)"
            case .iterationLimitReached:
                result = "error: iteration limit reached"
            default:
                break
            }
        }

        return result
    }

    /// Line-windowed read (Claude Code Read parity): return lines
    /// [offset, offset+limit) 1-based with an explicit range header so the
    /// model knows exactly which window it got and can page further. The
    /// 8000-char web bound still applies inside the window.
    static func windowedRead(_ content: String, path: String, offset: Int, limit: Int?) -> String {
        let lines = content.components(separatedBy: "\n")
        let total = lines.count
        let start = max(1, offset)
        guard start <= total else {
            return "error: offset \(start) is beyond the end of \(path) (\(total) lines)"
        }
        let end: Int
        if let limit = limit, limit > 0 {
            end = min(start + limit - 1, total)
        } else {
            end = total
        }
        let slice = lines[(start - 1)..<end].joined(separator: "\n")
        let header = "[\(path): lines \(start)–\(end) of \(total)]"
        let charCap = 8000
        guard slice.count > charCap else { return "\(header)\n\(slice)" }
        let head = String(slice.prefix(charCap))
        return "\(header)\n\(head)\n\n[truncated within window: showing first \(charCap) chars of lines \(start)–\(end). Narrow the window with limit/offset to read more.]"
    }

    /// Web-chat-friendly bounded read: vendor chats split large pastes into
    /// parts and free models answer EACH part instead of honoring the
    /// continuation header (audit: Kimi answered mid-split, killing the turn).
    /// 8000 chars keeps a tool_result within ~2 chunks; the range header
    /// tells the model exactly what it got so it can request the next window.
    static func webBoundedRead(_ content: String, path: String) -> String {
        let limit = 8000
        guard content.count > limit else { return content }
        let head = content.prefix(limit)
        let lineHint = content.count > limit
            ? "\n\n[truncated: lines 1–\(head.filter { $0 == "\n" }.count + 1) of \(content.filter { $0 == "\n" }.count + 1); file has \(content.count) chars total. Ask to read more with a wider range if needed.]"
            : ""
        return head + lineHint
    }
}
