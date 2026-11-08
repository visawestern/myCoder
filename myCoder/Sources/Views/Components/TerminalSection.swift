import SwiftUI
import Foundation

/// Правая панель «Терминал»: активные и завершённые фоновые команды
/// (директива 2026-11-09). Команда модели выполняется отдельно, видна здесь,
/// можно раскрыть и посмотреть вывод, остановить, или открыть полный
/// терминал. По завершении результат уже ушёл модели — чат продолжается.
struct TerminalSection: View {
    @EnvironmentObject var appState: AppState
    @State private var tasks: [BackgroundCommandTask] = []
    @State private var expandedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if tasks.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                    Text(L.t(AppLocalizationKey.locTerminalEmpty))
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                }
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
    }

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

    private func row(_ task: BackgroundCommandTask) -> some View {
        let isExpanded = expandedID == task.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
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
                Button(action: { withAnimation { expandedID = isExpanded ? nil : task.id } }) {
                    Text(task.displayTitle)
                        .interfaceFont(size: 11, design: .monospaced)
                        .foregroundColor(Color.mimo.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(HandCursorButtonStyle())
                Spacer(minLength: 0)
                if !task.isCompleted {
                    Button(action: {
                        Task { await BackgroundCommandCenter.shared.cancel(id: task.id) }
                    }) {
                        Image(systemName: "stop.circle")
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .help(L.t(AppLocalizationKey.locTerminalCancel))
                } else {
                    Text(task.exitCode == 0 ? "0" : "\(task.exitCode ?? -1)")
                        .interfaceFont(size: 10, design: .monospaced)
                        .foregroundColor(task.exitCode == 0 ? Color.mimo.success : Color.mimo.error)
                }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.command)
                        .interfaceFont(size: 10, design: .monospaced)
                        .foregroundColor(Color.mimo.textSecondary)
                        .lineLimit(2)
                    Text(task.output.isEmpty ? "(нет вывода)" : task.output)
                        .interfaceFont(size: 10, design: .monospaced)
                        .foregroundColor(Color.mimo.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(12)
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
        }
        .padding(.vertical, 2)
    }

    private func refresh() {
        Task {
            tasks = await BackgroundCommandCenter.shared.snapshot()
        }
    }
}
