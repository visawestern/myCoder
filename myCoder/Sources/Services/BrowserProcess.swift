import Foundation
import Darwin

/// Процесс-менеджер браузера AntiBrowser: запуск, ожидание готовности,
/// watchdog-перезапуск и завершение. Один процесс на всё приложение.
@MainActor
final class BrowserProcess {

    struct Config {
        static let defaultProfileDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyCoder/AntiBrowserProfile")

        var profileDir: URL = defaultProfileDir
        var apiPort: Int = 5390
        var engine: AntiBrowserEngineInfo

        var apiBase: String { "http://127.0.0.1:\(apiPort)" }

        /// The engine's only command-line option is the persistent profile.
        /// Window behavior belongs to engine code and profile preferences.
        var launchArguments: [String] { ["--user-data-dir=\(profileDir.path)"] }
    }

    private(set) var config: Config
    private var process: Process?
    private var lockFileURL: URL?
    private var engineLogHandle: FileHandle?
    /// Проба живости не должна убивать браузер на одиночном таймауте:
    /// под нагрузкой (несколько тяжёлых сайтов) UI-поток отвечает медленнее
    /// 2 с, и раньше watchdog принимал это за смерть процесса. Теперь нужен
    /// ряд подряд идущих неудачных проб.
    private var consecutiveProbeFailures = 0
    private static let probeTimeout: TimeInterval = 5
    private static let probeFailureThreshold = 3

    init(config: Config) {
        self.config = config
    }

    /// Лог движка рядом с профилем: раньше stderr уходил в /dev/null, и
    /// причина завершения браузера была невидима.
    private var engineLogURL: URL {
        config.profileDir.appendingPathComponent("antibrowser-engine.log")
    }

    // MARK: - Состояние

    var isRunning: Bool {
        guard let process, process.isRunning else { return false }
        return true
    }

    /// Живой ли процесс браузера сейчас отвечает на локальный REST API.
    func isReachable(timeout: TimeInterval = 2) async -> Bool {
        guard let url = URL(string: "\(config.apiBase)/version") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return false
        }
        return true
    }

    // MARK: - Запуск

    /// Запускает (или переиспользует) браузер и ждёт готовности REST API.
    func ensureRunning(timeout: TimeInterval = 60) async throws {
        if await isReachable() {
            // Порт занят живым браузером. Считаем его своим только если
            // процесс известен нам и жив, либо есть наш lock-файл.
            if isOwnedProcessAlive() {
                return
            }
            throw BrowserProcessError.portOccupied(port: config.apiPort)
        }
        try launchSilently()
        try await waitUntilReady(timeout: timeout)
    }

    private func launchSilently() throws {
        guard FileManager.default.fileExists(atPath: config.engine.binaryURL.path) else {
            throw EngineLocatorError.notFound
        }
        // Профиль и lock-файл.
        let fm = FileManager.default
        try fm.createDirectory(at: config.profileDir, withIntermediateDirectories: true)
        lockFileURL = config.profileDir.appendingPathComponent("mycoder.lock")
        try? fm.removeItem(at: lockFileURL!)

        let process = Process()
        process.executableURL = config.engine.binaryURL
        // Минимум следов в командной строке: профиль — единственный
        // обязательный аргумент. Геометрия окна задаётся кодом движка
        // (browser_window_state.cc: принудительно за экраном), первый запуск и
        // восстановление сессии — префсами профиля (prepareProfileForEngine).
        prepareProfileForEngine()
        process.arguments = config.launchArguments
        let handle = openEngineLog()
        process.standardOutput = handle ?? FileHandle.nullDevice
        process.standardError = handle ?? FileHandle.nullDevice
        try process.run()
        self.process = process
        writeLockFile(pid: process.processIdentifier)
        log("launch pid=\(process.processIdentifier) args=\(config.launchArguments.joined(separator: " "))")
    }

    /// Готовит профиль к запуску БЕЗ «светящихся» флагов командной строки:
    /// первый запуск уже пройден (first_run_completed), восстановление окон
    /// из сессии запрещено (session.restore_on_startup=4), геометрия окна —
    /// за экраном (browser.window_placement). Плюс сам движок принудительно
    /// ставит окно за экран в коде (browser_window_state.cc).
    private func prepareProfileForEngine() {
        // Local State: отметить первый запуск как пройденный; запретить
        // стартовое окно (движок запускается без окна, оно создаётся по
        // кнопке «Войти»).
        mutateJSON(at: config.profileDir.appendingPathComponent("Local State")) { json in
            json["first_run_completed"] = true
            var ab = json["antibrowser"] as? [String: Any] ?? [:]
            ab["no_startup_window"] = true
            json["antibrowser"] = ab
        }
        // Default/Preferences: не восстанавливать окна; геометрия — за экраном.
        let prefs = config.profileDir
            .appendingPathComponent("Default", isDirectory: true)
            .appendingPathComponent("Preferences")
        mutateJSON(at: prefs) { json in
            var session = json["session"] as? [String: Any] ?? [:]
            session["restore_on_startup"] = 4  // никогда
            json["session"] = session
            var browser = json["browser"] as? [String: Any] ?? [:]
            browser["window_placement"] = [
                "left": -4000,
                "top": 0,
                "width": 1280,
                "height": 800,
            ]
            json["browser"] = browser
        }
    }

    /// Читает JSON-файл профиля (или создаёт), применяет правку и пишет обратно.
    private func mutateJSON(at url: URL, _ edit: (inout [String: Any]) -> Void) {
        var json: [String: Any]
        if let data = try? Data(contentsOf: url),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = parsed
        } else {
            json = [:]
        }
        edit(&json)
        guard let out = try? JSONSerialization.data(withJSONObject: json,
                                                    options: [.sortedKeys]) else {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try? out.write(to: url, options: .atomic)
        log("профиль подготовлен: \(url.lastPathComponent)")
    }

    // MARK: - Готовность

    func waitUntilReady(timeout: TimeInterval = 60) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isReachable() {
                return
            }
            if let process, !process.isRunning {
                throw BrowserProcessError.exitedEarly
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw BrowserProcessError.timeout(seconds: timeout)
    }

    // MARK: - Watchdog

    /// Проверяет живость и перезапускает, если процесс умер или API молчит
    /// несколько проб подряд. Одиночный медленный ответ не считается смертью:
    /// под нагрузкой UI-поток браузера отвечает дольше короткого таймаута.
    func watchdogRestartIfNeeded() async throws {
        guard let process else { return }
        if await isReachable(timeout: Self.probeTimeout) {
            if consecutiveProbeFailures > 0 {
                log("watchdog: API снова отвечает после \(consecutiveProbeFailures) неудачных проб")
            }
            consecutiveProbeFailures = 0
            return
        }
        guard process.isRunning else {
            log("watchdog: процесс завершился (status=\(process.terminationStatus), reason=\(process.terminationReason.rawValue)) — перезапуск")
            consecutiveProbeFailures = 0
            terminate()
            try await ensureRunning()
            return
        }
        consecutiveProbeFailures += 1
        log("watchdog: API не отвечает \(consecutiveProbeFailures)/\(Self.probeFailureThreshold)")
        guard consecutiveProbeFailures >= Self.probeFailureThreshold else { return }
        consecutiveProbeFailures = 0
        log("watchdog: API молчит \(Self.probeFailureThreshold) проб подряд — перезапуск движка")
        terminate()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await ensureRunning()
    }

    // MARK: - Завершение

    /// Зачищает любой процесс, слушающий порт движка (по умолчанию 5390).
    /// Страховка для выхода из приложения: даже если движок был поднят мимо
    /// EngineStatusCenter (например, вручную для отладки), myCoder не должен
    /// оставлять его жить в фоне (живой прогон 2026-11-04).
    static func terminateAnyRunningEngine(apiPort: Int = 5390) {
        let probe = "http://127.0.0.1:\(apiPort)/version"
        guard let url = URL(string: probe) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.5
        let sem = DispatchSemaphore(value: 0)
        var alive = false
        URLSession.shared.dataTask(with: req) { _, response, _ in
            alive = (response as? HTTPURLResponse)?.statusCode != nil
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 0.6)
        guard alive else { return }
        // Порт отвечает — ищем PID через lsof и шлём SIGTERM.
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-nP", "-iTCP:\(apiPort)", "-sTCP:LISTEN", "-t"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in out.split(separator: "\n") {
                if let pid = Int(line.trimmingCharacters(in: .whitespaces)) {
                    posixKill(pid: pid_t(pid))
                }
            }
        } catch {
            // lsof недоступен — двигаемся дальше, EngineStatusCenter уже остановлен.
        }
    }

    private static func posixKill(pid: Int32) {
        if Darwin.kill(pid, SIGTERM) == 0 {
            Thread.sleep(forTimeInterval: 0.5)
            if Darwin.kill(pid, 0) == 0 { _ = Darwin.kill(pid, SIGKILL) }
        }
    }

    func terminate() {
        guard let process else { return }
        if process.isRunning {
            log("terminate: отправляю SIGTERM pid=\(process.processIdentifier)")
            process.interrupt() // SIGTERM: мягкое завершение.
        }
        // Даём шанс корректно закрыться.
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        if process.isRunning {
            log("terminate: SIGTERM не сработал, kill pid=\(process.processIdentifier)")
            process.terminate() // kill.
        }
        log("terminate: выход pid=\(process.processIdentifier) status=\(process.terminationStatus) reason=\(process.terminationReason.rawValue)")
        if let lockFileURL {
            try? FileManager.default.removeItem(at: lockFileURL)
        }
        engineLogHandle?.closeFile()
        engineLogHandle = nil
        self.process = nil
    }

    // MARK: - Лог движка

    /// Открывает лог движка на дозапись (переживает перезапуски — иначе
    /// следы предыдущего падения теряются) и возвращает handle для stdout/stderr.
    private func openEngineLog() -> FileHandle? {
        let fm = FileManager.default
        let url = engineLogURL
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil) else {
                return nil
            }
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return nil
        }
        try? handle.seekToEnd()
        engineLogHandle?.closeFile()
        engineLogHandle = handle
        return handle
    }

    private func log(_ message: String) {
        guard let handle = engineLogHandle else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[myCoder \(stamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    // MARK: - Singleton

    private func isOwnedProcessAlive() -> Bool {
        if let process, process.isRunning {
            return true
        }
        guard let lockFileURL,
              let pidText = try? String(contentsOf: lockFileURL, encoding: .utf8),
              let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0,
              kill(pid, 0) == 0 else {
            return false
        }
        return true
    }

    private func writeLockFile(pid: Int32) {
        guard let lockFileURL else { return }
        let text = "\(pid)\n"
        _ = try? text.write(to: lockFileURL, atomically: true, encoding: .utf8)
    }
}

enum BrowserProcessError: LocalizedError {
    case portOccupied(port: Int)
    case timeout(seconds: TimeInterval)
    case exitedEarly

    var errorDescription: String? {
        switch self {
        case .portOccupied(let port):
            return "Порт \(port) занят другим браузером. Закройте его или смените порты в настройках myCoder."
        case .timeout(let seconds):
            return "Браузер не стал доступен за \(Int(seconds)) с."
        case .exitedEarly:
            return "Браузер завершился сразу после запуска."
        }
    }
}
