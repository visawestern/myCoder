import Foundation
import Testing
@testable import myCoder

/// TDD-набор для аудита B1: тяжёлые долгие/мутирующие запросы не должны
/// блокировать единую очередь `NWListener` — иначе быстрые GET-чтения
/// (`/api/state`, `/api/chats`) стоят до 660с за долгим POST. Чистый
/// помощник `isHeavyRoute` классифицирует маршруты; фактическая отправка
/// тяжёлых выполняется на отдельной `actionQueue`.
@Suite("MyCoderAPIServer queue partition (B1)")
struct MyCoderAPIServerQueueTests {

    @Test("Быстрые GET-чтения не считаются тяжёлыми")
    func readsAreLight() {
        #expect(!MyCoderAPIServer.isHeavyRoute(method: "GET", path: "/api/state"))
        #expect(!MyCoderAPIServer.isHeavyRoute(method: "GET", path: "/api/chats"))
        #expect(!MyCoderAPIServer.isHeavyRoute(method: "GET", path: "/api/providers"))
        #expect(!MyCoderAPIServer.isHeavyRoute(method: "GET", path: "/api/messages"))
        #expect(!MyCoderAPIServer.isHeavyRoute(method: "GET", path: "/api/actions"))
        #expect(!MyCoderAPIServer.isHeavyRoute(method: "GET", path: "/api/web-login-status"))
    }

    @Test("Мутирующие POST уходят на тяжёлую очередь")
    func mutationsAreHeavy() {
        #expect(MyCoderAPIServer.isHeavyRoute(method: "POST", path: "/api/action"))
        #expect(MyCoderAPIServer.isHeavyRoute(method: "POST", path: "/api/send"))
        #expect(MyCoderAPIServer.isHeavyRoute(method: "POST", path: "/api/select"))
        #expect(MyCoderAPIServer.isHeavyRoute(method: "POST", path: "/api/context-preview"))
        #expect(MyCoderAPIServer.isHeavyRoute(method: "POST", path: "/api/refresh-models"))
        #expect(MyCoderAPIServer.isHeavyRoute(method: "POST", path: "/api/save-session"))
        #expect(MyCoderAPIServer.isHeavyRoute(method: "POST", path: "/api/evaluate"))
        #expect(MyCoderAPIServer.isHeavyRoute(method: "POST", path: "/api/markdown-perf/reset"))
    }

    @Test("Долгие GET (inspect/scroll/screenshot) тоже тяжёлые")
    func longReadsAreHeavy() {
        #expect(MyCoderAPIServer.isHeavyRoute(method: "GET", path: "/api/inspect"))
        #expect(MyCoderAPIServer.isHeavyRoute(method: "GET", path: "/api/scroll"))
        #expect(MyCoderAPIServer.isHeavyRoute(method: "GET", path: "/api/screenshot"))
    }
}
