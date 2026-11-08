import Testing
import Foundation
@testable import myCoder

/// Фоновый терминал (директива 2026-11-09): команда, запущенная моделью,
/// выполняется в фоне, не блокируя отправку новых сообщений; статус виден в
/// правом сайдбаре; по завершении результат уходит модели.
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
}
