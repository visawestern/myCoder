import Foundation

/// Фаза жизненного цикла движка AntiBrowser.
enum EnginePhase: Equatable {
    case idle
    case locating
    case launching
    case ready(AntiBrowserEngineInfo)
    case error(String)

    static func == (lhs: EnginePhase, rhs: EnginePhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.locating, .locating), (.launching, .launching):
            return true
        case (.ready(let a), .ready(let b)):
            return a.appURL == b.appURL
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Центр состояния движка: ищет AntiBrowser, запускает процесс, конфигурирует
/// менеджер вкладок (`AntiBrowserTabManager`) и следит за живостью процесса.
/// Мост создаётся на чат (`AntiBrowserAutomationBridge`), через общий
/// менеджер вкладок — по одному браузеру и одной вкладке на чат.
@MainActor
final class EngineStatusCenter: ObservableObject {

    static let shared = EngineStatusCenter()

    @Published private(set) var phase: EnginePhase = .idle

    private var browserProcess: BrowserProcess?
    private var watchdogTask: Task<Void, Never>?
    private var didConfigureTabs = false

    private init() {}

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// Возвращает готовность движка или понятную ошибку.
    func requireEngine() throws {
        guard isReady else {
            switch phase {
            case .error(let message):
                throw NSError(domain: "EngineStatusCenter", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            case .launching, .locating:
                throw NSError(domain: "EngineStatusCenter", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Движок ещё запускается, повторите через секунду"])
            default:
                throw NSError(domain: "EngineStatusCenter", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Движок AntiBrowser не запущен"])
            }
        }
    }

    /// Поднимает движок: поиск → запуск → готовность → конфигурация вкладок.
    func start() async {
        guard !isReady else { return }

        phase = .locating
        guard let engine = EngineLocator.locate() else {
            phase = .error(EngineLocatorError.notFound.localizedDescription)
            return
        }

        phase = .launching
        var config = BrowserProcess.Config(engine: engine)
        if let apiPort = UserDefaults.standard.object(forKey: "engine.apiPort") as? Int {
            config.apiPort = apiPort
        }

        let process = BrowserProcess(config: config)
        browserProcess = process
        do {
            try await process.ensureRunning()
        } catch {
            phase = .error(error.localizedDescription)
            return
        }

        if !didConfigureTabs {
            AntiBrowserTabManager.shared.configure(apiPort: config.apiPort,
                                                  profileDir: config.profileDir)
            didConfigureTabs = true
        }
        phase = .ready(engine)
        startWatchdog()
    }

    func stop() {
        watchdogTask?.cancel()
        watchdogTask = nil
        browserProcess?.terminate()
        browserProcess = nil
        phase = .idle
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, self.isReady else { return }
                guard let process = self.browserProcess else { return }
                // Решение о перезапуске принимает сам BrowserProcess:
                // одиночная медленная проба API не должна убивать живой движок.
                do {
                    try await process.watchdogRestartIfNeeded()
                } catch {
                    self.phase = .error(error.localizedDescription)
                    return
                }
            }
        }
    }
}
