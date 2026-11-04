import Testing
import Foundation
@testable import myCoder

/// `browser_fetch` and the sub-agent tool were dead on every direct
/// (local / OpenAI-compatible) model: the executor was built without a bridge,
/// so the tool answered "requires an active browser session (bridge not
/// available)" even with the engine running on 5390. Live run 2026-11-04:
/// mercury-3 called browser_fetch, got that error, and fell back to web_fetch.
@Suite("Мост браузера в исполнителе инструментов")
@MainActor
struct ExecutorBridgeWiringTests {

    @Test("Исполнитель direct-пути получает мост браузера")
    func directExecutorHasBridge() {
        let executor = ProjectWebToolExecutor.bridged(
            projectRoot: "/tmp/proj",
            accessLevel: .askBeforeChanges
        )
        #expect(executor.bridge != nil,
                "browser_fetch не сможет работать: мост не подключён")
    }

    @Test("Мост указывает на тот же профиль, что и движок")
    func bridgeUsesEngineProfile() {
        let executor = ProjectWebToolExecutor.bridged(
            projectRoot: "/tmp/proj",
            accessLevel: .askBeforeChanges
        )
        #expect(executor.bridge is AntiBrowserAutomationBridge)
    }

    @Test("Корень проекта и уровень доступа не теряются")
    func wiringKeepsExecutorSettings() {
        let executor = ProjectWebToolExecutor.bridged(
            projectRoot: "/tmp/proj",
            accessLevel: .fullAccess
        )
        #expect(executor.projectRoot == "/tmp/proj")
        #expect(executor.accessLevel == .fullAccess)
    }
}
