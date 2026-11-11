import Testing
import Foundation
@testable import myCoder

/// Аудит B2: состояние приложения должно жить на главном акторе.
/// Аудит B1 (остаток): сервер обязан быть полностью асинхронным — без
/// семафоров, без блокировки потоков и с отдельной задачей на запрос.
///
/// Эти проверки фиксируют оба свойства: класс изолирован, а обработчики
/// переходят на главный актор через `await`, а не через ожидание семафора.
@MainActor
@Suite("B2: AppState изолирован, сервер полностью асинхронный")
struct AppStateMainActorTests {

    @Test("Класс AppState помечен @MainActor")
    func classIsMainActor() throws {
        let source = try RepoRoot.appStateSourceText
        #expect(source.contains("@MainActor\nclass AppState: ObservableObject"))
    }

    @Test("В сервере не осталось ни одного семафора")
    func serverHasNoSemaphores() throws {
        let source = try RepoRoot.apiServerSourceText
        #expect(!source.contains("DispatchSemaphore"))
        #expect(!source.contains("Thread.sleep"))
    }

    @Test("Каждый запрос обслуживается отдельной задачей")
    func eachRequestGetsItsOwnTask() throws {
        let source = try RepoRoot.apiServerSourceText
        #expect(source.contains("Task(priority: priority)"))
        #expect(source.contains("await self.routeRequest("))
        #expect(source.contains("private func routeRequest"))
        #expect(source.contains(") async -> String {"))
    }

    @Test("Чтение состояния с фоновой задачи попадает на главный поток")
    func backgroundReadLandsOnMainThread() async {
        let landedOnMain = await Task.detached {
            await MyCoderAPIServer.mainRead({ Thread.isMainThread })
        }.value
        #expect(landedOnMain)
    }
}
