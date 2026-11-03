import Testing
import Foundation
@testable import myCoder

/// Фейковый источник запуска движка: считает вызовы start().
final class FakeEngineBootstrap: EngineBootstrapping {
    var isReady: Bool
    var startCount = 0
    init(isReady: Bool = false) { self.isReady = isReady }
    func start() async {
        startCount += 1
        isReady = true
    }
}

/// TDD: движок браузера стартует ЛЕНИВО — только когда реально нужен
/// (веб-чат, вход в провайдер, спецпоиск), а не при старте приложения.
@Suite("Ленивый запуск движка (lazy engine start)")
@MainActor
struct LazyEngineStartTests {

    /// Временный профиль с токеном в Local State.
    private func makeProfile(token: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lazy-engine-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state: [String: Any] = [
            "antibrowser": [
                "agent_api": ["token": token],
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: state)
        try! data.write(to: dir.appendingPathComponent("Local State"))
        return dir
    }

    @Test func startsWhenEngineNotReadyEvenWithToken() async {
        let profile = makeProfile(token: "abc123")
        let fake = FakeEngineBootstrap(isReady: false)
        let bridge = AntiBrowserAutomationBridge(tabKey: "k|global|x", profileDir: profile)
        bridge.engineBootstrap = fake
        await bridge.ensureEngineStartedIfNeeded()
        #expect(fake.startCount == 1, "движок должен запуститься, если не готов")
    }

    @Test func doesNotStartWhenAlreadyReady() async {
        let profile = makeProfile(token: "abc123")
        let fake = FakeEngineBootstrap(isReady: true)
        let bridge = AntiBrowserAutomationBridge(tabKey: "k|global|x", profileDir: profile)
        bridge.engineBootstrap = fake
        await bridge.ensureEngineStartedIfNeeded()
        #expect(fake.startCount == 0, "готовый движок не должен перезапускаться")
    }

    @Test func doesNotStartWithoutProfileDir() async {
        let fake = FakeEngineBootstrap(isReady: false)
        let bridge = AntiBrowserAutomationBridge(tabKey: "k|global|x", profileDir: nil)
        bridge.engineBootstrap = fake
        await bridge.ensureEngineStartedIfNeeded()
        #expect(fake.startCount == 0, "без профиля (тесты) движок не запускается")
    }

    @Test func doesNotStartWithoutBootstrap() async {
        let profile = makeProfile(token: "abc123")
        let bridge = AntiBrowserAutomationBridge(tabKey: "k|global|x", profileDir: profile)
        bridge.engineBootstrap = nil
        await bridge.ensureEngineStartedIfNeeded()
        // просто не должно упасть; start некому вызвать
        #expect(true)
    }

    @Test func startsOnlyOnceAcrossCalls() async {
        let profile = makeProfile(token: "abc123")
        let fake = FakeEngineBootstrap(isReady: false)
        let bridge = AntiBrowserAutomationBridge(tabKey: "k|global|x", profileDir: profile)
        bridge.engineBootstrap = fake
        await bridge.ensureEngineStartedIfNeeded()
        await bridge.ensureEngineStartedIfNeeded()
        #expect(fake.startCount == 1, "повторный вызов не должен запускать снова")
    }

    @Test func managerBridgeWithoutConfigStillSeesProfile() async {
        // До конфигурации EngineStatusCenter менеджер должен давать мосту
        // дефолтный профиль — иначе ленивый старт невозможен.
        let manager = AntiBrowserTabManager.shared
        let bridge = manager.bridge(tabKey: "lazy-test|global|provider-login")
        let fake = FakeEngineBootstrap(isReady: false)
        bridge.engineBootstrap = fake
        await bridge.ensureEngineStartedIfNeeded()
        #expect(fake.startCount == 1,
                "мост без явного конфига должен видеть профиль и уметь стартовать")
    }
}
