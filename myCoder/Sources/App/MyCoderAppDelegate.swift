import AppKit
import Foundation
import Darwin

/// AppDelegate: единственная точка, которая гарантирует закрытие движка при
/// выходе из приложения. До этого myCoder при выходе не глушил форк Chromium:
/// процесс оставался жить в фоне и продолжал слушать порт 5390 (живой прогон
/// 2026-11-04). Это нарушает правило «движок запускается только из myCoder»
/// и съедает память после закрытия приложения.
@MainActor
final class MyCoderAppDelegate: NSObject, NSApplicationDelegate {
    private var didShutdown = false
    private let lock = NSLock()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI App не вызывает applicationWillTerminate при SIGTERM/SIGINT.
        // Без хендлеров движок остаётся жить в фоне после kill (живой прогон
        // 2026-11-04). Хендлеры ставим один раз на старте.
        installSignalHandlers()
    }

    /// Вызывается при обычном выходе (Cmd+Q, меню док-станции, osascript quit).
    func applicationWillTerminate(_ notification: Notification) {
        shutdownOnce()
    }

    /// Подстраховка: SwiftUI App не всегда вызывает applicationWillTerminate
    /// при внешних сигналах (SIGTERM/SIGINT от kill), а пользователь ждёт,
    /// что движок умрёт вместе с приложением (живой прогон 2026-11-04).
    /// Signal handler вызывает ту же логику и затем сам завершает процесс.
    func installSignalHandlers() {
        // SwiftUI App не вызывает applicationWillTerminate при SIGTERM/SIGINT
        // от kill — процесс умирает мгновенно, движок остаётся жить в фоне
        // (живой прогон 2026-11-04). dispatch_source даёт нормальный
        // Swift-обработчик: убиваем движок, потом сами завершаемся.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                self?.shutdownOnce()
                _exit(0)
            }
            src.resume()
            // Храним, чтобы не освободился.
            signalSources.append(src)
        }
        // SIGTERM по умолчанию убивает процесс немедленно — отключаем это.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
    }

    private var signalSources: [DispatchSourceSignal] = []

    private func shutdownOnce() {
        // Один раз. Повторный вызов (например, при SIGTERM после нашего же
        // stop()) не должен трогать процесс, который уже остановлен.
        lock.lock()
        let already = didShutdown
        didShutdown = true
        lock.unlock()
        guard !already else { return }

        // API-сервер должен перестать отвечать раньше, чем мы убьём движок:
        // иначе последний запрос может уйти в мост, который сейчас умрёт.
        MyCoderAPIServer.shared.stop()
        EngineStatusCenter.shared.stop()
        // На случай если движок был поднят мимо центра — зачищаем и сам
        // процесс по его порту.
        BrowserProcess.terminateAnyRunningEngine()
    }
}
