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
    /// Номер сообщения модели, во время которого выполняется инструмент:
    /// правки файлов привязываются к нему для точного отката диалога.
    let messageId: String?
    let accessLevel: AccessLevel
    /// True when the open chat has no project folder. File-changing tools are
    /// then refused until the user creates a project (see `ProjectlessWriteLogic`).
    let isProjectless: Bool
    /// Host hook that asks the user to create a project folder. Input is the
    /// suggested folder name; output is the created project root, or nil when
    /// the user declined. Called only for file-changing tools in a projectless
    /// chat, before any write happens.
    var projectlessWritePrompt: (@MainActor (String) async -> String?)?
    /// Home directory for user-global reads (installed skills). Defaults to
    /// the real home; injectable so skill tests use a temp sandbox.
    let homeDirectory: URL
    var bridge: BrowserAutomationBridge?
    var selectors: WebVendorSelectors?
    /// When true, a successful write/edit of a code file appends the language
    /// server's diagnostics to the tool result. Production turns enable it;
    /// unit tests stay hermetic (no server processes).
    var automaticDiagnostics = false

    init(projectRoot: String,
         fileManager: FileManager = .default,
         undoManager: ProjectUndoManager? = nil,
         sessionId: String? = nil,
         messageId: String? = nil,
         accessLevel: AccessLevel = .askBeforeChanges,
         isProjectless: Bool = false,
         projectlessWritePrompt: (@MainActor (String) async -> String?)? = nil,
         homeDirectory: URL? = nil) {
        self.projectRoot = projectRoot
        self.fileManager = fileManager
        self.undoManager = undoManager
        self.sessionId = sessionId
        self.messageId = messageId
        self.accessLevel = accessLevel
        self.isProjectless = isProjectless
        self.projectlessWritePrompt = projectlessWritePrompt
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    /// Исполнитель с подключённым мостом браузера.
    ///
    /// Direct-модели (локальные и OpenAI-совместимые) исполняют инструменты
    /// на хосте, но исполнитель создавался без моста — и `browser_fetch`
    /// отвечал «requires an active browser session (bridge not available)»
    /// даже при живом движке на 5390 (живой прогон 2026-11-04: mercury-3
    /// получил эту ошибку и ушёл на web_fetch). Мост берётся из общего
    /// менеджера, поэтому профиль и порт те же, что у движка.
    @MainActor
    static func bridged(projectRoot: String,
                        accessLevel: AccessLevel = .askBeforeChanges,
                        sessionId: String? = nil,
                        messageId: String? = nil,
                        isProjectless: Bool = false,
                        tabKey: String = "tools") -> ProjectWebToolExecutor {
        var executor = ProjectWebToolExecutor(
            projectRoot: projectRoot,
            undoManager: (try? ProjectUndoManager(projectPath: projectRoot)),
            sessionId: sessionId,
            messageId: messageId,
            accessLevel: accessLevel,
            isProjectless: isProjectless
        )
        executor.bridge = AntiBrowserTabManager.shared.bridge(tabKey: tabKey)
        executor.automaticDiagnostics = true
        return executor
    }

    func execute(_ call: WebToolCall) async -> String {
        // The project gate runs before any side effect AND before the access
        // prompt: asking the user to allow a write that cannot legally happen
        // would be noise. A projectless chat must never touch disk.
        if let refusal = await projectlessWriteRefusal(for: call) {
            return refusal
        }
        // The access gate runs before any side effect: a gated tool is never
        // executed, it is reported back to the model as needing approval.
        // NOTE: when the driver already collected an Allow verdict it calls
        // execute(_:userApproved:) — this gate must not fire twice (F4).
        if WebToolAccessGate.permission(for: call, accessLevel: accessLevel, projectRoot: projectRoot) == .requireApproval {
            return approvalMessage(for: call)
        }
        return await run(call)
    }

    func execute(_ call: WebToolCall, userApproved: Bool) async -> String {
        if let refusal = await projectlessWriteRefusal(for: call) {
            return refusal
        }
        if userApproved { return await run(call) }
        // Do not re-enter execute(_:) here: it would run the project gate a
        // second time and ask the user twice.
        if WebToolAccessGate.permission(for: call, accessLevel: accessLevel, projectRoot: projectRoot) == .requireApproval {
            return approvalMessage(for: call)
        }
        return await run(call)
    }

    /// Resolve a tool path against the project root.
    ///
    /// An absolute path is used as it is: `appendingPathComponent` would glue
    /// it onto the root and produce a path that does not exist, so every
    /// absolute path outside the project resolved to a missing file.
    func url(for path: String) -> URL {
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
                return await fileWriteResult(path: url.path, displayPath: path, contentCount: content.count)
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
            // Every rejected edit answers with a specific reason instead of
            // writing something the model did not intend (OpenCode parity).
            guard !oldStr.isEmpty else {
                return "error: 'old' is empty — nothing to match in \(path). Read the file and pass the exact text to replace."
            }
            guard oldStr != newStr else {
                return "error: No changes to apply: 'old' and 'new' are identical in \(path). Read the file and re-emit the call with the intended change."
            }
            let occurrences = content.components(separatedBy: oldStr).count - 1
            guard occurrences > 0 else {
                return "error: 'old' text not found in \(path). The file changed or the text differs — read it with read_file and copy the exact current text, including indentation."
            }
            guard occurrences == 1 else {
                return "error: 'old' matches \(occurrences) places in \(path). Include more surrounding context so the replacement targets exactly one place."
            }
            let updated = content.replacingOccurrences(of: oldStr, with: newStr)
            do {
                try performFileOperation(operation: "edit_file", fileURL: url, execute: {
                    try updated.write(to: url, atomically: true, encoding: .utf8)
                })
                return await fileEditResult(path: url.path, displayPath: path)
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
            //
            // Фоновый запуск (директива 2026-11-09): команда выполняется
            // отдельным процессом через BackgroundCommandCenter — она не
            // прерывается новой отправкой сообщений, видна в правом
            // сайдбаре, а результат возвращается модели после завершения.
            let cmd = call.arguments["command"] ?? ""
            return await runCommandInBackground(cmd, workingDirectory: projectRoot)
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
        case .codeSearch:
            let query = (call.arguments["query"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return "error: missing query" }
            let requested = call.arguments["limit"].flatMap { Int($0.filter(\.isNumber)) } ?? 8
            let limit = min(max(requested, 1), 20)
            do {
                let hits = try CodeIndexService.search(
                    projectPath: projectRoot,
                    query: query,
                    limit: limit
                )
                return CodeIndexService.renderSearch(query: query, hits: hits)
            } catch {
                return "error: code index failed: \(error.localizedDescription)"
            }
        case .readSymbol:
            let id = (call.arguments["id"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                if !id.isEmpty {
                    return CodeIndexService.renderSymbol(
                        try CodeIndexService.readSymbol(projectPath: projectRoot, id: id)
                    )
                }
                guard let path = call.arguments["path"],
                      let name = call.arguments["name"] else {
                    return "error: missing id (or path + name)"
                }
                let line = call.arguments["line"].flatMap { Int($0.filter(\.isNumber)) }
                return CodeIndexService.renderSymbol(
                    try CodeIndexService.readSymbol(
                        projectPath: projectRoot,
                        path: path,
                        name: name,
                        line: line
                    )
                )
            } catch {
                return "error: \(error.localizedDescription)"
            }
        case .lsp:
            return await lspToolResult(call: call)
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
        case .browserFetch:
            return await fetchBrowserPage(arguments: call.arguments)
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
    func performFileOperation(operation: String, fileURL: URL, execute: () throws -> Void) throws {
        guard let undoManager, let sessionId else {
            try execute()
            return
        }
        try undoManager.executeWithUndo(operation: operation, filePath: fileURL.path,
                                        sessionId: sessionId, messageId: messageId,
                                        execute: execute)
        try undoManager.db.recordRequestHistory(
            sessionId: sessionId,
            type: "file_edit",
            payload: "{\"path\":\"\(fileURL.path)\",\"operation\":\"\(operation)\"}"
        )
    }


    /// Injected by the chat panel for API-backed routes: launches the task as
    /// a real sub-agent chat (child session in the database, listed in the
    /// right panel). nil keeps the legacy browser-session path.
    var subagentLauncher: ((String, String) async -> String)?

    /// Запуск команды через фоновый терминал: процесс самостоятелен, UI и
    /// отправка новых сообщений не блокируются; тут только ждём итог.
    ///
    /// Перед запуском команда проходит проверку безопасности внутренней
    /// моделью (аудит A6). Опасная или непроверенная команда возвращает
    /// ошибку и не запускается.
    private func runCommandInBackground(_ command: String, workingDirectory: String) async -> String {
        if let block = await ProjectShellRunner.safetyBlock(
            command: command,
            workingDirectory: workingDirectory
        ) {
            return BackgroundCommandLogic.renderResult(
                output: block.output,
                exitCode: Int(block.exitCode)
            )
        }
        let id = await BackgroundCommandCenter.shared.start(
            command: command,
            workingDirectory: workingDirectory,
            sessionID: sessionId
        )
        let task = await BackgroundCommandCenter.shared.awaitCompletion(id: id)
        return BackgroundCommandLogic.renderResult(output: task.output, exitCode: task.exitCode ?? -1)
    }

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
