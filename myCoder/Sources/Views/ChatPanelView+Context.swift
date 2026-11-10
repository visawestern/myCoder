import SwiftUI
import AppKit

extension ChatPanelView {
    /// Imports the files chosen in the file picker.
    ///
    /// Kept out of the view body on purpose: the body expression is large
    /// enough that the Swift type-checker times out ("unable to type-check
    /// this expression in reasonable time") when this closure is inlined.
    func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let name = url.lastPathComponent
            let ext = url.pathExtension
            let type = FileType.from(ext: ext)
            let path = url.path
            attachmentStore.appendFile(FileInfo(name: name, type: type, path: path))
        }
    }

    /// Empty-chat state with the centered composer.
    ///
    /// Kept as a separate view property so `body` stays within the Swift
    /// type-checker's budget.
    @ViewBuilder
    var centeredInputState: some View {
        let presentation = ChatLoadingIndicatorLogic.presentation(
            isLoading: messageStore.isLoadingMessages,
            messageCount: messageStore.messages.count
        )
        EmptyChatStateView(
            messageText: $messageText,
            attachmentStore: attachmentStore,
            showFilePicker: $showFilePicker,
            messageQueue: messageQueue,
            onSend: sendMessage,
            onStop: stopGeneration,
            isLoading: visibleSessionIsStreaming,
            isLoadingChat: presentation == .centered,
            onForceSendQueued: forceSendQueued,
            onEditQueued: editQueuedMessage
        )
    }

    /// The send path must not depend on the user opening the @ picker first.
    /// It uses the already-built index only: the baseline is built once in the
    /// background when a workspace opens, and FSEvents keep it fresh via
    /// `ProjectFileIndexEventUpdater` — the send path never scans.
    static func recordsForPointContext(projectPath: String) async -> [FileIndexRecord] {
        guard !projectPath.isEmpty else { return [] }
        return await Task.detached(priority: .utility) {
            ProjectFileIndexStore.load(projectPath: projectPath)
        }.value
    }

    /// One bounded local planning pass (R9). The model sees only the top-K
    /// entities and answers with a JSON plan; a missing local model, an empty
    /// candidate set, a timeout or a rejected answer all become a visible
    /// fallback that the deterministic plan then replaces.

    /// `/remember <text>`: store the fact in the project database and confirm
    /// it in chat. A write failure is reported, never swallowed.
    @MainActor
    func rememberProjectFact(_ text: String) async {
        let projectPath = appState.selectedWorkspace?.path ?? ""
        guard !projectPath.isEmpty else {
            messageStore.append(Message(
                role: .assistant,
                content: L.t(AppLocalizationKey.locMemoryFailed),
                isFinished: true
            ))
            return
        }
        guard let chunk = ProjectMemoryExtraction.chunk(text: text, projectPath: projectPath) else {
            messageStore.append(Message(
                role: .assistant,
                content: L.t(AppLocalizationKey.locMemoryUsage),
                isFinished: true
            ))
            return
        }

        let saved: Result<Void, Error> = await Task.detached(priority: .utility) {
            do {
                let store = try ProjectDatabaseManager.manager(forProjectPath: projectPath).makeMemoryStore()
                try store.upsert(chunk)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch saved {
        case .success:
            messageStore.append(Message(
                role: .assistant,
                content: "\(L.t(AppLocalizationKey.locMemorySaved)): \(chunk.text)",
                isFinished: true
            ))
        case .failure:
            messageStore.append(Message(
                role: .assistant,
                content: L.t(AppLocalizationKey.locMemoryFailed),
                isFinished: true
            ))
        }
    }

    /// `/goal` → ЦЕЛЬ: applies the goal command (create/start/pause/resume/
    /// delete/list) via GoalStore and replies in chat.
    @MainActor
    func runGoalCommand(_ command: GoalCommand) async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let session = appState.selectedSession
        // Bind the goal to the open chat and its project (user directive
        // 2026-11-08) — `/goal` must not create a global goal that migrates
        // between chats.
        let context = GoalContextLogic.context(
            chatID: messageStore.currentSessionID ?? session?.id,
            sessionDirectory: session?.directory,
            selectedWorkspacePath: appState.selectedWorkspace?.path
        )
        let reply: String
        var launchedGoalID: UUID?
        do {
            let result = try GoalService.apply(
                command,
                homeDirectory: home,
                language: appState.appLanguage,
                context: context
            )
            // Команда start/resume запускает автономный цикл: полный промпт
            // цели уходит в чат как юзер (с контекстом).
            if case .start = command, let active = result.goals.first(where: { $0.state == .active }) {
                launchedGoalID = active.id
            }
            reply = result.reply.isEmpty ? "🎯 Целей нет." : result.reply
        } catch {
            reply = "Ошибка команды цели: \(error.localizedDescription)"
        }
        if let launchedGoalID {
            _ = GoalLauncher.launch(
                goalID: launchedGoalID,
                homeDirectory: home,
                language: appState.appLanguage,
                fallbackChatID: context.chatID
            )
        }
        messageStore.append(Message(role: .assistant, content: reply, isFinished: true))
    }
}
