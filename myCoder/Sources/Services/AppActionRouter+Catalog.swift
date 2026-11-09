import Foundation

/// Каталог действий — контракт обнаружения для automation-клиентов.
/// Вынесен из основного файла, чтобы `AppActionRouter.swift` оставался
/// ≤600 строк (требование проекта).
@MainActor
extension AppActionRouter {
    // MARK: - Catalog

    static let catalog: [[String: Any]] = [
        action("app.state", "Return the full UI/state snapshot", []),
        action("app.activate", "Bring the app to the front", []),
        action("app.settings.open", "Open Settings", [param("tab", "string", false, "SettingsTab raw value")]),
        action("app.settings.close", "Close Settings", []),
        action("app.sidebar.toggle", "Show/hide the sidebar", [param("visible", "bool", false, nil)]),
        action("app.terminal.toggle", "Show/hide the terminal panel", [param("visible", "bool", false, nil)]),
        action("app.goal.toggle", "Show/hide the goal/right panel", [param("visible", "bool", false, nil)]),
        action("app.search.toggle", "Show/hide search", [param("visible", "bool", false, nil)]),
        action("app.notifications.toggle", "Show/hide notifications", [param("visible", "bool", false, nil)]),
        action("app.language.set", "Change UI language", [param("language", "string", true, "English|Russian|... or en|ru|es|fr|de|zh|ja|ko|pt|ar")]),
        action("app.agentMode.set", "Change agent mode", [param("mode", "string", true, "Build|Plan|Compose")]),
        action("app.accessLevel.set", "Change permission level", [param("level", "string", true, "Ask before changes|Edit automatically|Full access")]),
        action("app.variant.set", "Change reasoning variant", [param("variant", "string", true, nil)]),
        action("app.flag.set", "Set a boolean app flag", [
            param("name", "string", true, "maxTokens|askBeforeChanges|inputDropdownEnabled"),
            param("value", "bool", true, nil)
        ]),

        action("project.list", "List workspaces", []),
        action("project.state", "Return the selected project state", []),
        action("project.create", "Create/register a project and optionally open the spec wizard", [
            param("name", "string", false, "Defaults to the folder name"),
            param("path", "string", true, "Absolute folder path"),
            param("mode", "string", false, "empty|wizard"),
            param("createDirectory", "bool", false, "Create the folder when missing")
        ]),
        action("project.open", "Open an existing folder as a workspace", [
            param("path", "string", true, nil),
            param("name", "string", false, nil),
            param("createDirectory", "bool", false, nil)
        ]),
        action("project.select", "Select a workspace by id or path", [
            param("id", "string", false, nil),
            param("path", "string", false, nil)
        ]),
        action("project.finder.open", "Reveal a folder in Finder", [param("path", "string", false, "Defaults to the selected workspace")]),
        action("project.creation.begin", "Open the New Project sheet", [param("mode", "string", false, "empty|wizard")]),
        action("project.creation.cancel", "Close the New Project sheet", []),

        action("wizard.state", "Return the spec-wizard draft, turns, revisions and nodes", [param("path", "string", false, nil)]),
        action("wizard.save", "Update the wizard brief/model roles", [
            param("path", "string", false, nil),
            param("goal", "string", false, nil),
            param("stack", "string", false, nil),
            param("constraints", "string", false, nil),
            param("plannerModel", "string", false, nil),
            param("coderModel", "string", false, nil)
        ]),
        action("wizard.interview.start", "Ask the planner for the first interview question", [param("path", "string", false, nil)]),
        action("wizard.answer", "Answer the current planner question", [
            param("path", "string", false, nil),
            param("answer", "string", true, nil)
        ]),
        action("wizard.spec.generate", "Generate a new specification revision", [param("path", "string", false, nil)]),
        action("wizard.spec.edit", "Save an edited specification as a new revision", [
            param("path", "string", false, nil),
            param("markdown", "string", true, nil)
        ]),
        action("wizard.decompose", "Generate the atomic decomposition for the latest revision", [param("path", "string", false, nil)]),
        action("wizard.node.status", "Set a decomposition node status", [
            param("path", "string", false, nil),
            param("nodeId", "string", false, nil),
            param("key", "string", false, nil),
            param("status", "string", true, "pending|running|done|failed|blocked|skipped")
        ]),
        action("wizard.node.start", "Create a coding chat for the next runnable node and queue its prompt", [
            param("path", "string", false, nil),
            param("nodeId", "string", false, nil),
            param("key", "string", false, nil)
        ]),
        action("wizard.node.next", "Return the next runnable node", [param("path", "string", false, nil)]),
        action("wizard.node.linkSession", "Link a chat session to a decomposition node", [
            param("path", "string", false, nil),
            param("nodeId", "string", false, nil),
            param("key", "string", false, nil),
            param("sessionId", "string", false, nil),
            param("state", "string", false, "active|done")
        ]),
        action("wizard.finish", "Finish the wizard (forced or complete)", [
            param("path", "string", false, nil),
            param("forced", "bool", false, nil)
        ]),

        action("session.list", "List chat sessions", []),
        action("session.select", "Select a chat session", [param("id", "string", true, nil)]),
        action("session.new", "Create a standalone chat", [param("title", "string", false, nil)]),
        action("session.rename", "Rename a chat", [param("id", "string", true, nil), param("title", "string", true, nil)]),
        action("session.delete", "Delete a chat", [param("id", "string", true, nil)]),
        action("session.export", "Export a chat transcript as Markdown", [
            param("id", "string", true, nil),
            param("path", "string", false, "Destination .md file; defaults to ~/Downloads")
        ]),
        action("chat.send", "Send a message", [
            param("message", "string", true, nil),
            param("chatId", "string", false, nil),
            param("providerId", "string", false, nil),
            param("modelId", "string", false, nil)
        ]),
        action("chat.stop", "Stop the current generation", []),
        action("context.compaction.stop", "Stop the running model-switch compaction", []),
        action("context.compaction.rollback", "Roll back the model-switch compaction", []),
        action("context.compaction.retry", "Compact again after a stop, a failure or a rollback", []),
        action("context.compaction.chooseModel", "Switch to a model with a larger context window instead of compacting", [
            param("providerID", "string", true, "Provider of the model to switch to"),
            param("modelID", "string", true, "Model to switch to")
        ]),
        action("toolApproval.resolve", "Allow or deny a pending local tool approval", [
            param("id", "string", true, "Approval id from the app log"),
            param("approved", "bool", true, "true = Allow once, false = Deny")
        ]),

        action("browser.fetch", "Run browser_fetch through the app-owned AntiBrowser engine", [
            param("url", "string", true, "http/https URL"),
            param("selector", "string", false, "CSS selector whose text is returned; mutually exclusive with script"),
            param("script", "string", false, "JavaScript expression; mutually exclusive with selector"),
            param("click", "string", false, "CSS selector to click before reading"),
            param("screenshot", "bool|string", false, "Request a PNG attachment"),
            param("limit", "int|string", false, "Maximum page/selector text characters")
        ]),

        action("provider.list", "List configured providers and models", []),
        action("provider.select", "Select a provider", [param("id", "string", true, nil)]),
        action("model.select", "Select a model", [param("id", "string", true, nil)]),
        action("model.list", "List models for the selected provider", []),

        action("git.refresh", "Refresh git status for the selected session", []),
        action("git.commit", "Commit all changes", [param("message", "string", true, nil)]),
        action("git.push", "Push the current branch", []),
        action("git.branch.checkout", "Checkout a branch", [param("branch", "string", true, nil)]),

        action("ui.tree", "Dump the accessibility tree of the key window", [
            param("depth", "int", false, "Default 8"),
            param("limit", "int", false, "Default 1200")
        ]),
        action("ui.click", "Press a button by identifier/title/path/index", [
            param("identifier", "string", false, nil),
            param("title", "string", false, nil),
            param("role", "string", false, "Default AXButton"),
            param("path", "string", false, "Tree path such as 0.2.1"),
            param("index", "int", false, "Index in the flattened tree")
        ]),
        action("ui.setValue", "Set the value of a text field by identifier/title/path/index", [
            param("identifier", "string", false, nil),
            param("title", "string", false, nil),
            param("path", "string", false, nil),
            param("index", "int", false, nil),
            param("value", "string", true, nil)
        ]),

        action("goal.state", "Return the ЦЕЛЬ goals state (list + active goal)", []),
        action("goal.list", "List ЦЕЛЬ goals", []),
        action("goal.create", "Create a ЦЕЛЬ goal", [param("title", "string", true, nil)]),
        action("goal.start", "Start the active ЦЕЛЬ goal", []),
        action("goal.pause", "Pause the active ЦЕЛЬ goal", []),
        action("goal.resume", "Resume a paused ЦЕЛЬ goal", []),
        action("goal.delete", "Delete a ЦЕЛЬ goal", [param("index", "int", false, "Defaults to the latest")]),
        action("goal.verify", "Run the devil's-advocate verification on the active goal and report whether its plan is really done", [
            param("answer", "string", false, "The model's last assistant answer to check")
        ]),
        action("ui.screenshot", "Capture an app-window screenshot (same as the Скриншоты menu)", [
            param("path", "string", false, "Optional explicit destination .png path")
        ]),
        action("ui.screenshots.list", "List the saved screenshots", []),
        action("chat.rollback", "Roll the chat back to a user request (full undo of files + dialog)", [
            param("messageId", "string", true, "User message id to roll back to"),
            param("chatId", "string", false, "Chat session id (defaults to the selected chat)")
        ])
    ]

    private static func action(_ name: String, _ description: String, _ params: [[String: Any]]) -> [String: Any] {
        ["name": name, "description": description, "params": params]
    }

    private static func param(_ name: String, _ type: String, _ required: Bool, _ description: String?) -> [String: Any] {
        var row: [String: Any] = ["name": name, "type": type, "required": required]
        if let description { row["description"] = description }
        return row
    }
}
