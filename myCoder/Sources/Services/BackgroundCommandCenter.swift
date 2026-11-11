import Foundation

/// Фоновый терминал (директива 2026-11-09): команда запускается отдельным
/// процессом, выполняется независимо от хода агента/UI и не прерывается
/// новой отправкой сообщений. Статус доступен сайдбару, а по завершении —
/// результат возвращается ожидающему (цикл агента).
actor BackgroundCommandCenter {

    static let shared = BackgroundCommandCenter()

    /// Сколько ждём фоновую команду, прежде чем принудительно завершить её.
    static let defaultTimeoutSeconds: TimeInterval = 600

    private var tasks: [String: BackgroundCommandTask] = [:]
    private var continuations: [String: CheckedContinuation<BackgroundCommandTask, Never>] = [:]
    private var runningProcesses: [String: Process] = [:]

    private init() {}

    /// Запустить команду в фоне. Возвращает id задачи.
    ///
    /// Здесь стоит только быстрая жёсткая защита от катастроф (без сети).
    /// Смысловая проверка внутренней моделью выполняется на входе инструмента
    /// (`ProjectWebToolExecutor.runCommandInBackground`), чтобы не держать
    /// актор фонового терминала на время сетевого вызова.
    @discardableResult
    func start(command: String,
               workingDirectory: String,
               timeoutSeconds: TimeInterval = BackgroundCommandCenter.defaultTimeoutSeconds) -> String {
        let task = BackgroundCommandTask(command: command, workingDirectory: workingDirectory)
        if let reason = DestructiveCommandGuard.blockReason(for: command) {
            var blocked = task
            blocked.state = .completed
            blocked.output = "error: \(reason)"
            blocked.exitCode = 2
            blocked.finishedAt = Date()
            tasks[task.id] = blocked
            NotificationCenter.default.post(name: .backgroundCommandChanged, object: nil)
            return task.id
        }
        tasks[task.id] = task
        let id = task.id
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProjectShellRunner.shellPath)
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        runningProcesses[id] = process

        var buffer = Data()
        let lock = NSLock()
        func accumulate(_ data: Data) {
            lock.lock()
            buffer.append(data)
            lock.unlock()
        }
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            accumulate(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            accumulate(handle.availableData)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let center = BackgroundCommandCenter.shared
        process.terminationHandler = { proc in
            // Чтение остатков пайпов после выхода процесса.
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            lock.lock()
            let leftoverOut = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
            let leftoverErr = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
            buffer.append(leftoverOut)
            buffer.append(leftoverErr)
            lock.unlock()

            let text = String(data: buffer, encoding: .utf8) ?? ""
            let lines = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            var nonEmpty = lines.filter { !$0.isEmpty }
            let exitCode = Int(proc.terminationStatus)
            if exitCode != 0 {
                nonEmpty.append("(exit \(exitCode))")
            }
            Task {
                await center.complete(
                    id: id,
                    output: nonEmpty.joined(separator: "\n"),
                    exitCode: exitCode,
                    timedOut: Date() > deadline
                )
            }
        }

        do {
            try process.run()
        } catch {
            Task {
                await center.complete(
                    id: id,
                    output: "error: failed to launch: \(error.localizedDescription)",
                    exitCode: -1,
                    timedOut: false
                )
            }
        }
        return id
    }

    /// Ждать завершения задачи и получить её итог.
    func awaitCompletion(id: String) async -> BackgroundCommandTask {
        if let task = tasks[id], task.isCompleted {
            return task
        }
        return await withCheckedContinuation { continuation in
            continuations[id] = continuation
        }
    }

    /// Все задачи: активные + завершённые (новые сверху).
    func snapshot() -> [BackgroundCommandTask] {
        let all = Array(tasks.values)
        let active = BackgroundCommandLogic.sortedActive(all.filter { !$0.isCompleted })
        let finished = BackgroundCommandLogic.sortedFinished(all.filter(\.isCompleted))
        return active + finished
    }

    func activeTasks() -> [BackgroundCommandTask] {
        BackgroundCommandLogic.sortedActive(tasks.values.filter { !$0.isCompleted })
    }

    func cancel(id: String) {
        runningProcesses[id]?.terminate()
    }

    private func complete(id: String, output: String, exitCode: Int, timedOut: Bool) {
        guard var task = tasks[id] else { return }
        task.state = timedOut ? .terminated : .completed
        task.output = output
        task.exitCode = exitCode
        task.finishedAt = Date()
        tasks[id] = task
        runningProcesses.removeValue(forKey: id)
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: task)
        }
        NotificationCenter.default.post(name: .backgroundCommandChanged, object: nil)
        SidebarAttentionNotification.post()
    }
}

extension Notification.Name {
    static let backgroundCommandChanged = Notification.Name("myCoderBackgroundCommandChanged")
}
