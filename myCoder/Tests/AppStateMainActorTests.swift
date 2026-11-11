import Testing
import Foundation
@testable import myCoder

/// Аудит B2: состояние приложения должно жить на главном акторе.
///
/// `AppState` читают и пишут обработчики интерфейса и локальный HTTP-сервер.
/// Если класс не изолирован, два потока могут увидеть наполовину обновлённое
/// состояние. Эти проверки фиксируют изоляцию класса и то, что сервер
/// действительно переходит на главный поток за чтением.
@MainActor
@Suite("B2: AppState изолирован на главном акторе")
struct AppStateMainActorTests {

    @Test("Класс AppState помечен @MainActor")
    func classIsMainActor() throws {
        let source = try RepoRoot.appStateSourceText
        #expect(source.contains("@MainActor\nclass AppState: ObservableObject"))
    }

    @Test("Сервер читает состояние через переход на главный актор")
    func serverReadHelperExists() throws {
        let source = try RepoRoot.apiServerSourceText
        #expect(source.contains("static func onMainRead<T>(_ body: @MainActor () -> T) -> T"))
        #expect(source.contains("DispatchQueue.main.sync"))
    }

    @Test("Чтение с фоновой очереди выполняется на главном потоке")
    func backgroundReadLandsOnMainThread() async {
        let landedOnMain = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let flag = MyCoderAPIServer.onMainRead { Thread.isMainThread }
                continuation.resume(returning: flag)
            }
        }
        #expect(landedOnMain)
    }
}
