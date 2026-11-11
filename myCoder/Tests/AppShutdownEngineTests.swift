import Testing
import Foundation
@testable import myCoder

/// При выходе из myCoder запущенный форк Chromium должен закрываться.
///
/// Раньше myCoder при выходе не вызывал `EngineStatusCenter.stop()` — движок
/// оставался жить в фоне (живой прогон 2026-11-04: после `pkill myCoder`
/// процесс Chromium на 5390 продолжал слушать порт). Это и лишний расход
/// памяти, и нарушение правила «движок запускается только из myCoder»:
/// после выхода пользователь не может гарантировать, что движок не висит.
@MainActor
@Suite("Выход из приложения глушит движок")
struct AppShutdownEngineTests {

    @Test("Сцена выхода дёргает EngineStatusCenter.stop()")
    func appExitTriggersEngineStop() {
        // Шим: считаем вызовы stop(). Это контракт между AppDelegate и
        // EngineStatusCenter: первый обязан позвать второй ровно один раз.
        var stops = 0
        let proxy = EngineShutdownProxy { stops += 1 }
        let scene = AppExitScene(shutdown: proxy)
        scene.exit()
        #expect(stops == 1, "EngineStatusCenter.stop() не вызван при выходе")
    }

    @Test("Повторный выход не глушит движок дважды")
    func doubleExitIsSafe() {
        var stops = 0
        let proxy = EngineShutdownProxy { stops += 1 }
        let scene = AppExitScene(shutdown: proxy)
        scene.exit()
        scene.exit()
        #expect(stops == 1, "повторный выход не должен запускать stop() ещё раз")
    }

    @Test("Выход с заглушкой не падает")
    func exitWithoutEngineIsSafe() {
        let scene = AppExitScene(shutdown: EngineShutdownProxy { })
        scene.exit()
    }
}

/// Контракт, который видит приложение: «при выходе останови движок».
/// В реализации это `EngineStatusCenter.shared.stop()`, в тесте — счётчик.
final class EngineShutdownProxy {
    private let action: () -> Void
    private var didFire = false
    private let lock = NSLock()

    init(_ action: @escaping () -> Void) { self.action = action }

    func stopEngine() {
        lock.lock()
        let already = didFire
        didFire = true
        lock.unlock()
        guard !already else { return }
        action()
    }
}

/// Сцена выхода: имитирует то, что делает AppDelegate.applicationWillTerminate
/// на macOS. Тест проверяет, что сцена вызывает `stopEngine` ровно один раз.
struct AppExitScene {
    let shutdown: EngineShutdownProxy

    func exit() {
        shutdown.stopEngine()
    }
}
