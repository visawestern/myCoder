import SwiftUI
import Foundation
import AppKit

/// Правая панель «Терминал»: активные и завершённые фоновые команды
/// (директива 2026-11-09). Команда модели выполняется отдельно, видна здесь,
/// можно раскрыть и посмотреть вывод, остановить, скопировать команду/вывод
/// или убрать завершённую строку. Список строго привязан к открытому чату и
/// показывает не больше 10 последних команд (директива 2026-11-13).
struct TerminalSection: View {
    @EnvironmentObject var appState: AppState
    @State private var tasks: [BackgroundCommandTask] = []
    @State private var expandedID: String?
    @State private var copiedCommandID: String?
    @State private var copiedOutputID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if tasks.isEmpty {
                emptyState
            } else {
                ForEach(tasks) { task in
                    row(task)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .backgroundCommandChanged)) { _ in
            refresh()
        }
        .onChange(of: appState.selectedSession?.id) { _ in
            // The panel belongs to one chat: switching chats must immediately
            // replace the list and close a row expanded in the previous chat.
            expandedID = nil
            refresh()
        }
    }

    /// Panel header: title, visible-command count and the full-terminal button.
    /// Input: none (reads `tasks`). Output: the header view. No side effects.
    private var header: some View {
        HStack {
            Image(systemName: "terminal")
                .interfaceFont(size: 12, weight: .semibold)
                .foregroundColor(Color.mimo.violet)
            Text(L.t(AppLocalizationKey.locTerminalTitle))
                .interfaceFont(size: 14, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)
            if !tasks.isEmpty {
                Text("\(tasks.count)")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
            }
            Spacer()
            Button(action: { appState.showTerminal = true }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locTerminalOpen))
        }
    }

    /// Empty state shown when the open chat has no background commands.
    /// Input: none. Output: the placeholder view. No side effects.
    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
            Text(L.t(AppLocalizationKey.locTerminalEmpty))
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textMuted)
        }
    }

    /// One command row: status, title, quick actions and (when expanded)
    /// command/output/working directory. Input: the task to render. Output:
    /// the row view. Depends on the copy/stop/remove helpers below.
    private func row(_ task: BackgroundCommandTask) -> some View {
        let isExpanded = expandedID == task.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusIcon(for: task)
                titleButton(for: task, isExpanded: isExpanded)
                Spacer(minLength: 0)
                if !task.isCompleted {
                    stopButton(for: task)
                }
                copyCommandButton(for: task)
                if task.isCompleted {
                    removeButton(for: task)
                    exitCodeLabel(for: task)
                }
            }
            if isExpanded {
                details(for: task)
            }
        }
        .padding(.vertical, 2)
    }

    /// Leading status indicator: spinner while running, result icon when done.
    /// Input: task. Output: icon view. No side effects.
    private func statusIcon(for task: BackgroundCommandTask) -> some View {
        Group {
            if task.isCompleted {
                Image(systemName: task.state == .terminated ? "xmark.circle" : "checkmark.circle")
                    .interfaceFont(size: 10)
                    .foregroundColor(task.state == .terminated ? Color.mimo.error : Color.mimo.success)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                    .frame(width: 10, height: 10)
            }
        }
    }

    /// Tappable command title that expands/collapses the output. Input: task
    /// and its current expansion flag. Output: button view. Depends on
    /// `expandedID`.
    private func titleButton(for task: BackgroundCommandTask, isExpanded: Bool) -> some View {
        Button(action: { withAnimation { expandedID = isExpanded ? nil : task.id } }) {
            Text(task.displayTitle)
                .interfaceFont(size: 11, design: .monospaced)
                .foregroundColor(Color.mimo.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(HandCursorButtonStyle())
    }

    /// Stop a running command. Input: task. Output: button view. Depends on
    /// `BackgroundCommandCenter.cancel`, which terminates the process; the
    /// awaiting agent turn then receives the terminated result.
    private func stopButton(for task: BackgroundCommandTask) -> some View {
        Button(action: { stop(task) }) {
            Image(systemName: "stop.circle")
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locTerminalCancel))
    }

    /// Copy the exact command line to the pasteboard. Input: task. Output:
    /// button view; shows a checkmark briefly after a successful copy.
    /// Depends on `copyToPasteboard` and `copiedCommandID`.
    private func copyCommandButton(for task: BackgroundCommandTask) -> some View {
        Button(action: {
            guard copyToPasteboard(task.command) else { return }
            markCopied(task.id, isOutput: false)
        }) {
            Image(systemName: copiedCommandID == task.id ? "checkmark" : "doc.on.doc")
                .interfaceFont(size: 10)
                .foregroundColor(copiedCommandID == task.id ? Color.mimo.success : Color.mimo.textMuted)
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locTerminalCopyCommand))
    }

    /// Remove a completed row from the panel. Running tasks are not offered
    /// this action because their agent turn still awaits the result. Input:
    /// task. Output: button view. Depends on `BackgroundCommandCenter.remove`.
    private func removeButton(for task: BackgroundCommandTask) -> some View {
        Button(action: { remove(task) }) {
            Image(systemName: "trash")
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(L.t(AppLocalizationKey.locTerminalRemove))
    }

    /// Exit-code badge of a finished command. Input: task. Output: text view.
    /// No side effects.
    private func exitCodeLabel(for task: BackgroundCommandTask) -> some View {
        Text(task.exitCode == 0 ? "0" : "\(task.exitCode ?? -1)")
            .interfaceFont(size: 10, design: .monospaced)
            .foregroundColor(task.exitCode == 0 ? Color.mimo.success : Color.mimo.error)
    }

    /// Expanded body: command, captured output with a copy button, and the
    /// working directory. Input: task. Output: detail view. Depends on
    /// `copyToPasteboard` and `copiedOutputID`.
    private func details(for task: BackgroundCommandTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.command)
                .interfaceFont(size: 10, design: .monospaced)
                .foregroundColor(Color.mimo.textSecondary)
                .lineLimit(2)
            HStack(alignment: .top, spacing: 4) {
                Text(task.output.isEmpty ? "(нет вывода)" : task.output)
                    .interfaceFont(size: 10, design: .monospaced)
                    .foregroundColor(Color.mimo.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(12)
                Button(action: {
                    guard copyToPasteboard(task.output) else { return }
                    markCopied(task.id, isOutput: true)
                }) {
                    Image(systemName: copiedOutputID == task.id ? "checkmark" : "doc.on.doc")
                        .interfaceFont(size: 9)
                        .foregroundColor(copiedOutputID == task.id ? Color.mimo.success : Color.mimo.textMuted)
                }
                .buttonStyle(HandCursorButtonStyle())
                .help(L.t(AppLocalizationKey.locTerminalCopyOutput))
            }
            Text(task.workingDirectory)
                .interfaceFont(size: 9, design: .monospaced)
                .foregroundColor(Color.mimo.textMuted)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mimo.backgroundAlt)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    /// Reload the visible list for the OPEN chat. Input: none. Output: none;
    /// updates `tasks` only if the same chat is still selected after the await
    /// (a slow snapshot must not leak another chat's commands). Depends on
    /// `AppState.selectedSession` and `BackgroundCommandCenter.snapshot`.
    private func refresh() {
        let sessionID = appState.selectedSession?.id
        Task {
            let visible = await BackgroundCommandCenter.shared.snapshot(sessionID: sessionID)
            guard appState.selectedSession?.id == sessionID else { return }
            tasks = visible
        }
    }

    /// Stop a running task. Input: task. Output: none. Depends on
    /// `BackgroundCommandCenter.cancel`; the changed notification refreshes
    /// the list when the process actually exits.
    private func stop(_ task: BackgroundCommandTask) {
        Task { await BackgroundCommandCenter.shared.cancel(id: task.id) }
    }

    /// Remove a completed task. Input: task. Output: none. Depends on
    /// `BackgroundCommandCenter.remove`; the notification triggers `refresh`.
    private func remove(_ task: BackgroundCommandTask) {
        Task { _ = await BackgroundCommandCenter.shared.remove(id: task.id) }
    }

    /// Put text on the system pasteboard. Input: arbitrary text. Output:
    /// `true` when the pasteboard accepted it. No app dependencies, so this
    /// helper can move to any macOS target unchanged.
    private func copyToPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Briefly show the "copied" checkmark on one of the row's copy buttons.
    /// Input: task id and whether the output (vs command) was copied. Output:
    /// none. Depends on `DispatchQueue.main`; the reset is UI-only.
    private func markCopied(_ id: String, isOutput: Bool) {
        if isOutput {
            copiedOutputID = id
        } else {
            copiedCommandID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if isOutput, copiedOutputID == id {
                copiedOutputID = nil
            } else if !isOutput, copiedCommandID == id {
                copiedCommandID = nil
            }
        }
    }
}
