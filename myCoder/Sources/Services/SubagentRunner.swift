import Foundation

/// Runs a `task` tool call as a real sub-agent chat: a child ChatSession is
/// created in the same database as the parent chat, every model response is
/// persisted there, and the final text is returned to the parent model as the
/// tool result. The right panel lists child sessions and navigation opens the
/// full transcript.
enum SubagentRunner {
    static let statusRunning = "running"
    static let statusDone = "done"
    static let statusFailed = "failed"

    /// Tools a sub-agent may run on its own. Anything that changes state
    /// (writes, git mutations, shell) is denied here — approvals belong to the
    /// parent chat, where the user sees the Allow/Deny card.
    static let readOnlyTools: Set<String> = [
        "read_file", "list_dir", "grep", "glob", "todo_read", "task_list",
        "git_status", "git_diff", "git_log", "web_fetch"
    ]

    static let maxToolIterations = 6
    static let maxTitleLength = 60

    /// Where the sub-agent model call goes. Mirrors the parent chat's send
    /// route so the child runs on the same provider the user selected.
    enum Transport {
        case autoFree
        case openAICompatible(baseURL: URL, apiKey: String, model: String)
        case unsupported(reason: String)
    }

    struct Context {
        let parentSessionID: String
        let projectKey: String
        let directory: String
        let projectRoot: String
        let transport: Transport
    }

    static func title(for description: String) -> String {
        let cleaned = description
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxTitleLength else {
            return cleaned.isEmpty ? "Sub-agent" : cleaned
        }
        return String(cleaned.prefix(maxTitleLength - 1)) + "…"
    }

    static func isReadOnly(_ call: WebToolCall) -> Bool {
        let canonical = WebToolProtocolEmulator.canonicalized(call).name
        return readOnlyTools.contains(canonical)
    }

    static func launch(description: String, prompt: String, context: Context) async -> String {
        let child = DatabaseBridge.shared.createSubagentSession(
            parentSessionID: context.parentSessionID,
            projectKey: context.projectKey,
            directory: context.directory,
            title: title(for: description)
        )
        NotificationCenter.default.post(name: .subagentSessionChanged, object: nil)

        DatabaseBridge.shared.saveMessage(
            Message(role: .user, content: prompt),
            sessionId: child.id
        )

        let systemPrompt = """
        You are a sub-agent working autonomously on a specific task for a parent agent.
        Task description: \(description)
        Work read-only: investigate, analyze and report. You cannot modify files —
        if changes are needed, describe exactly what the parent should do.
        Return a complete, self-contained result.
        """

        var conversation: [Message] = [
            Message(role: .system, content: systemPrompt),
            Message(role: .user, content: prompt)
        ]
        let executor = ProjectWebToolExecutor(
            projectRoot: context.projectRoot,
            accessLevel: .fullAccess
        )
        var finalText = ""
        var failed = false

        for _ in 0..<maxToolIterations {
            let response: String
            do {
                response = try await callModel(conversation: conversation, context: context)
            } catch {
                finalText = "error: \(error.localizedDescription)"
                failed = true
                break
            }
            DatabaseBridge.shared.saveMessage(
                Message(role: .assistant, content: response),
                sessionId: child.id
            )
            NotificationCenter.default.post(name: .subagentSessionChanged, object: nil)
            finalText = response
            let calls = WebToolProtocolEmulator.parseToolCalls(from: response)
            if calls.isEmpty || WebToolProtocolEmulator.isFinalResponse(response) {
                break
            }
            var resultsBlock = ""
            for call in calls {
                let result: String
                if !isReadOnly(call) {
                    result = "denied: \(call.name) may not run inside a sub-agent. Ask the parent agent to perform changes; report what you found instead."
                } else {
                    result = await executor.execute(call, userApproved: true)
                }
                resultsBlock += WebToolProtocolEmulator.formatToolResult(
                    name: call.name, result: result
                ) + "\n"
            }
            conversation.append(Message(role: .assistant, content: response))
            conversation.append(Message(role: .user, content: resultsBlock))
        }

        DatabaseBridge.shared.setSubagentStatus(
            sessionID: child.id,
            status: failed ? SubagentRunner.statusFailed : SubagentRunner.statusDone
        )
        NotificationCenter.default.post(name: .subagentSessionChanged, object: nil)
        return finalText
    }

    static func roleName(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }

    private static func callModel(conversation: [Message], context: Context) async throws -> String {
        switch context.transport {
        case .autoFree:
            var content = ""
            let stream = MyCoderAutoFreeClient.shared.chatCompletion(
                model: MyCoderAutoFreeClient.defaultModelID,
                messages: conversation.map { message in
                    MyCoderAutoFreeClient.Message(role: SubagentRunner.roleName(message.role), content: message.content)
                },
                parameters: ModelCallParameters(),
                tools: MyCoderAutoFreeClient.gateToolDefinitions(),
                toolChoice: "none",
                projectRoot: context.projectRoot,
                isGitRepo: false
            )
            for try await event in stream {
                if case .content(let text) = event {
                    content += text
                }
            }
            return content
        case .openAICompatible(let baseURL, let apiKey, let model):
            let result = try await DirectChatClient.send(
                baseURL: baseURL.absoluteString,
                apiKey: apiKey,
                model: model,
                messages: conversation.map { message in
                    DirectChatMessage(role: SubagentRunner.roleName(message.role), content: message.content)
                },
                parameters: ModelCallParameters()
            )
            return result.content
        case .unsupported(let reason):
            return "error: \(reason)"
        }
    }
}

extension Notification.Name {
    static let subagentSessionChanged = Notification.Name("com.mycoder.subagentSessionChanged")
}
