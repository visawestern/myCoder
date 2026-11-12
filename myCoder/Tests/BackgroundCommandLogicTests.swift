import Testing
import Foundation
@testable import myCoder

/// Фоновый терминал (директива 2026-11-09): команда, запущенная моделью,
/// выполняется в фоне, не блокируя отправку новых сообщений; статус виден в
/// правом сайдбаре; по завершении результат уходит модели.
@MainActor
@Suite("Фоновый терминал — логика")
struct BackgroundCommandLogicTests {

    @Test("Формат результата включает вывод и код возврата")
    func renderResultIncludesOutputAndExit() {
        let text = BackgroundCommandLogic.renderResult(output: "готово", exitCode: 0)
        #expect(text.contains("готово"))
        #expect(text.contains("exit 0"))
    }

    @Test("Активные задачи сортируются по времени запуска (новые сверху)")
    func activeTasksNewestFirst() {
        let old = BackgroundCommandTask(id: "1", command: "a", workingDirectory: "/", createdAt: Date(timeIntervalSince1970: 1000))
        let new = BackgroundCommandTask(id: "2", command: "b", workingDirectory: "/", createdAt: Date(timeIntervalSince1970: 2000))
        let sorted = BackgroundCommandLogic.sortedActive([old, new])
        #expect(sorted.map(\.id) == ["2", "1"])
    }

    @Test("Задача готовa, когда есть вывод и код возврата")
    func taskCompletedWhenOutputCaptured() {
        var task = BackgroundCommandTask(id: "1", command: "ls", workingDirectory: "/")
        #expect(!task.isCompleted)
        task.output = "file.txt"
        task.exitCode = 0
        #expect(task.isCompleted)
    }

    @Test("Терминал показывает только команды своего чата")
    func visibleTasksAreBoundToChat() {
        let mine = BackgroundCommandTask(
            id: "mine", command: "echo mine", workingDirectory: "/",
            sessionID: "chat-a"
        )
        let foreign = BackgroundCommandTask(
            id: "foreign", command: "echo foreign", workingDirectory: "/",
            sessionID: "chat-b"
        )
        let visible = BackgroundCommandLogic.visibleTasks(
            [mine, foreign], sessionID: "chat-a"
        )
        #expect(visible.map(\.id) == ["mine"])
    }

    @Test("Без выбранного чата терминал не показывает чужие команды")
    func visibleTasksEmptyWithoutChat() {
        let task = BackgroundCommandTask(
            id: "1", command: "echo", workingDirectory: "/", sessionID: "chat-a"
        )
        #expect(BackgroundCommandLogic.visibleTasks([task], sessionID: nil).isEmpty)
    }

    @Test("В терминале остаются только 10 последних команд чата")
    func visibleTasksKeepLastTen() {
        let tasks = (0..<14).map { index in
            BackgroundCommandTask(
                id: "\(index)",
                command: "echo \(index)",
                workingDirectory: "/",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                sessionID: "chat-a"
            )
        }
        let visible = BackgroundCommandLogic.visibleTasks(tasks, sessionID: "chat-a")
        #expect(visible.count == BackgroundCommandLogic.maxVisibleTasks)
        #expect(visible.map(\.id) == (4..<14).reversed().map(String.init))
    }

    @Test("Активные команды идут раньше завершённых, внутри — новые сверху")
    func visibleTasksOrderActiveFirst() {
        var finished = BackgroundCommandTask(
            id: "finished", command: "echo done", workingDirectory: "/",
            createdAt: Date(timeIntervalSince1970: 3000),
            sessionID: "chat-a"
        )
        finished.exitCode = 0
        finished.finishedAt = Date(timeIntervalSince1970: 4000)
        let active = BackgroundCommandTask(
            id: "active", command: "sleep 1", workingDirectory: "/",
            createdAt: Date(timeIntervalSince1970: 1000),
            sessionID: "chat-a"
        )
        let visible = BackgroundCommandLogic.visibleTasks(
            [finished, active], sessionID: "chat-a"
        )
        #expect(visible.map(\.id) == ["active", "finished"])
    }

    @Test("Заголовок задачи для сайдбара содержит команду")
    func titleContainsCommand() {
        let task = BackgroundCommandTask(id: "1", command: "find / -name '*.log'", workingDirectory: "/")
        #expect(task.displayTitle.contains("find"))
    }

    @Test("Фоновая команда выполняется и возвращает вывод")
    func backgroundRunReturnsOutput() async {
        let id = await BackgroundCommandCenter.shared.start(
            command: "echo hello-bg",
            workingDirectory: "/tmp"
        )
        let task = await BackgroundCommandCenter.shared.awaitCompletion(id: id)
        #expect(task.isCompleted)
        #expect(task.exitCode == 0)
        #expect(task.output.contains("hello-bg"))
    }

    @Test("Команда с ошибкой возвращает ненулевой код")
    func backgroundRunCapturesExitCode() async {
        let id = await BackgroundCommandCenter.shared.start(
            command: "exit 7",
            workingDirectory: "/tmp"
        )
        let task = await BackgroundCommandCenter.shared.awaitCompletion(id: id)
        #expect(task.isCompleted)
        #expect(task.exitCode == 7)
        #expect(task.output.contains("exit 7"))
    }

    @Test("Фоновая задача помнит чат, который её запустил")
    func backgroundRunKeepsSessionID() async {
        let sessionID = "chat-\(UUID().uuidString)"
        let id = await BackgroundCommandCenter.shared.start(
            command: "echo bound-to-chat",
            workingDirectory: "/tmp",
            sessionID: sessionID
        )
        let task = await BackgroundCommandCenter.shared.awaitCompletion(id: id)
        #expect(task.sessionID == sessionID)
        let mine = await BackgroundCommandCenter.shared.snapshot(sessionID: sessionID)
        #expect(mine.contains { $0.id == id })
        let foreign = await BackgroundCommandCenter.shared.snapshot(
            sessionID: "chat-other-\(UUID().uuidString)"
        )
        #expect(!foreign.contains { $0.id == id })
    }

    @Test("Завершённую задачу можно убрать, активную — нельзя")
    func removeOnlyCompletedTasks() async {
        let sessionID = "chat-\(UUID().uuidString)"
        let id = await BackgroundCommandCenter.shared.start(
            command: "echo removable",
            workingDirectory: "/tmp",
            sessionID: sessionID
        )
        _ = await BackgroundCommandCenter.shared.awaitCompletion(id: id)
        let removed = await BackgroundCommandCenter.shared.remove(id: id)
        #expect(removed)
        let snapshot = await BackgroundCommandCenter.shared.snapshot(sessionID: sessionID)
        #expect(!snapshot.contains { $0.id == id })

        let runningID = await BackgroundCommandCenter.shared.start(
            command: "sleep 30",
            workingDirectory: "/tmp",
            sessionID: sessionID
        )
        let runningRemoved = await BackgroundCommandCenter.shared.remove(id: runningID)
        #expect(!runningRemoved)
        await BackgroundCommandCenter.shared.cancel(id: runningID)
        _ = await BackgroundCommandCenter.shared.awaitCompletion(id: runningID)
    }
}
