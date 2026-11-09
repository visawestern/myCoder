import Foundation

/// Detailed, generated documentation for the emulated executor. Kept separate
/// from the compact web preamble so its existing paste budgets stay unchanged.
enum ToolInstructionGuide {
    static func build() -> String {
        build(tools: WebEmulatedTool.allCases, agentMode: .build)
    }

    static func notes(for tool: WebEmulatedTool) -> String {
        switch tool {
        case .readFile:
            return "path selects the file; offset is 1-based and limit counts lines. Page long files using successive windows. Image files return an ATTACHED_IMAGE marker instead of text."
        case .writeFile:
            return "path selects the destination and content is its complete replacement text. Parent directories are created if needed. Read existing content before overwriting a file."
        case .editFile:
            return "old must match exactly once, including whitespace. new replaces that one occurrence; empty old, identical old/new, missing matches and ambiguous matches return errors. Read the current file before retrying."
        case .listDir:
            return "path selects the directory; omitted path means the working directory. The result lists entry names."
        case .grep:
            return "pattern is the search expression; path scopes the search to a file or directory and defaults to the working directory. Inspect returned matches before editing."
        case .runCommand:
            return "command is shell text executed in the configured working directory with bounded execution. Check output and exit status. Read-only recognition is host policy; do not assume a command bypasses approval."
        case .gitStatus:
            return "Runs Git status in the configured project working directory. The current executor does not use path to select another repository or filter this output."
        case .gitDiff:
            return "staged=true selects the staged diff; otherwise the unstaged diff is returned. The current executor does not use path to filter this output."
        case .gitLog:
            return "limit bounds the number of commits (default 10). The current executor does not use path to filter commit history."
        case .gitBranch:
            return "With create=true and branch set, create a branch; otherwise list branches. Inspect repository state before changing it."
        case .gitCheckout:
            return "branch names the branch to switch to. Check the result for conflicts or dirty-worktree restrictions."
        case .gitCommit:
            return "message is the commit message. addAll=true stages all changes before committing; omit it to commit already staged changes. Inspect the diff before requesting a commit."
        case .gitPush:
            return "remote defaults to origin; branch optionally names the branch. This changes the remote repository and remains subject to host permission."
        case .gitPull:
            return "remote defaults to origin; branch optionally names the branch. Inspect the outcome for conflicts before continuing work."
        case .glob:
            return "pattern is a glob such as **/*.swift, not a regex. path chooses the search root and defaults to the working directory."
        case .codeSearch:
            return "query selects indexed symbols or code terms; limit bounds hits. Inspect incoming/outgoing graph neighbors and their confidence: heuristic links require confirmation from source."
        case .readSymbol:
            return "Use an id returned by code_search, or path plus name (optionally line to disambiguate). The host verifies current file content and refuses stale line numbers; refresh the search after a stale result."
        case .todoRead:
            return "No arguments. Read current task/checklist state before replacing or changing it."
        case .todoWrite:
            return "todos is the complete replacement array of id, content and status entries. Preserve unrelated tasks when updating; statuses are pending, in_progress or completed."
        case .task:
            return "description labels the task and prompt supplies the full delegated objective and constraints. subagentType names the requested role; actual runner availability and behavior depend on the active transport. Use the returned result as evidence."
        case .webFetch:
            return "url must use http/https. limit optionally bounds returned characters. This retrieves text over HTTP; use browser_fetch for DOM interaction or a browser screenshot."
        case .browserFetch:
            return "url must use http/https and navigates on every call. click runs before reading: click is a CSS selector for a page element. selector chooses an element's text; script is a JavaScript expression evaluated in the page; selector and script are mutually exclusive. With neither, return page text. limit bounds returned text for page/selector reads, not the serialized script result or image. screenshot=true requests a PNG returned as ATTACHED_IMAGE:image/png:<base64>; if that marker is absent, do not claim a screenshot was obtained. Browser/session availability is required. Example:\n```tool\n{\"name\": \"browser_fetch\", \"args\": {\"url\": \"https://example.com\", \"click\": \"button.details\", \"selector\": \"main\", \"screenshot\": \"true\", \"limit\": \"4000\"}}\n```"
        case .skill:
            return "Omit name to list installed skill IDs; provide a returned name to read that skill's instructions. This reads installed instructions and does not install or execute a skill automatically."
        case .taskCreate:
            return "content is the new task text; status is optional and uses pending, in_progress or completed. Keep the returned task ID for later updates."
        case .taskList:
            return "No arguments. Returns checklist tasks and IDs for task_update."
        case .taskUpdate:
            return "id identifies an existing task; content and status are optional updates. Read task_list first if the ID or current state is unknown."
        }
    }
}
