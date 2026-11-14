import Foundation
import Testing
@testable import myCoder

/// Правая панель: каждая секция (гит, трансляция, субагенты, терминал, план,
/// цель) — сворачиваемый спойлер, и состояние свёрнутости запоминается
/// отдельно для каждого чата.
///
/// Здесь проверяется чистая логика: ключи хранения, разбор сохранённой
/// строки, переключение и независимость чатов.
@Suite("Правая панель — свёрнутость секций по чатам")
struct RightPanelSpoilerLogicTests {

    // MARK: - Ключи

    @Test("Ключ хранения уникален для каждого чата")
    func scopeKeyIsPerChat() {
        let a = RightPanelSpoilerLogic.scopeKey(chatID: "chat-a")
        let b = RightPanelSpoilerLogic.scopeKey(chatID: "chat-b")
        #expect(a != b)
        #expect(a.hasPrefix(RightPanelSpoilerLogic.storagePrefix))
    }

    @Test("Без чата используется отдельный ключ, не совпадающий с именем чата")
    func anonymousScopeHasOwnKey() {
        let anonymous = RightPanelSpoilerLogic.scopeKey(chatID: nil)
        #expect(anonymous != RightPanelSpoilerLogic.scopeKey(chatID: ""))
        #expect(anonymous != RightPanelSpoilerLogic.scopeKey(chatID: "anonymous"))
        #expect(anonymous.hasSuffix(RightPanelSpoilerLogic.anonymousScope))
    }

    // MARK: - Разбор сохранённого значения

    @Test("Пустое или отсутствующее значение — ничего не свёрнуто")
    func emptyRawMeansAllExpanded() {
        #expect(RightPanelSpoilerLogic.decode(nil).isEmpty)
        #expect(RightPanelSpoilerLogic.decode("").isEmpty)
        #expect(RightPanelSpoilerLogic.decode("   ").isEmpty)
    }

    @Test("Известные секции разбираются, неизвестные отбрасываются")
    func decodeIgnoresUnknownTokens() {
        let decoded = RightPanelSpoilerLogic.decode("git, terminal ,nonsense,,goal")
        #expect(decoded == [.git, .terminal, .goal])
    }

    @Test("Кодирование и разбор дают исходный набор")
    func encodeDecodeRoundTrip() {
        let original: Set<RightPanelSection> = [.plan, .git, .goal]
        let raw = RightPanelSpoilerLogic.encode(original)
        #expect(RightPanelSpoilerLogic.decode(raw) == original)
    }

    @Test("Кодирование стабильно: один набор — одна строка")
    func encodeIsDeterministic() {
        let one: Set<RightPanelSection> = [.goal, .git, .terminal]
        let two: Set<RightPanelSection> = [.terminal, .goal, .git]
        #expect(RightPanelSpoilerLogic.encode(one) == RightPanelSpoilerLogic.encode(two))
    }

    // MARK: - Переключение

    @Test("Свежий чат: все секции развёрнуты")
    func freshChatExpandsEverything() {
        let collapsed: Set<RightPanelSection> = []
        for section in RightPanelSection.allCases {
            #expect(!RightPanelSpoilerLogic.isCollapsed(section, in: collapsed))
        }
    }

    @Test("Переключение сворачивает и разворачивает обратно")
    func toggleCollapsesAndRestores() {
        let collapsed = RightPanelSpoilerLogic.toggled(.terminal, in: [])
        #expect(RightPanelSpoilerLogic.isCollapsed(.terminal, in: collapsed))
        #expect(!RightPanelSpoilerLogic.isCollapsed(.git, in: collapsed))

        let restored = RightPanelSpoilerLogic.toggled(.terminal, in: collapsed)
        #expect(restored.isEmpty)
    }

    @Test("Секции независимы: сворачивание одной не трогает остальные")
    func sectionsAreIndependent() {
        var collapsed: Set<RightPanelSection> = []
        for section in RightPanelSection.allCases {
            collapsed = RightPanelSpoilerLogic.toggled(section, in: collapsed)
        }
        #expect(collapsed == Set(RightPanelSection.allCases))
    }

    // MARK: - Стартовое состояние

    @Test("Стартовое состояние свёрнутости — только живой хромкаст")
    func defaultCollapsedIsOnlyChromecast() {
        #expect(RightPanelSpoilerLogic.defaultCollapsed == [.chromecast])
        // Все элементы стартового набора — реальные секции, и кодирование
        // сохраняет их без потерь.
        #expect(RightPanelSpoilerLogic.decode(RightPanelSpoilerLogic.encode(
            RightPanelSpoilerLogic.defaultCollapsed)) == RightPanelSpoilerLogic.defaultCollapsed)
    }

    // MARK: - Совместимость

    @Test("Каждая секция имеет непустой стабильный идентификатор")
    func identifiersAreStable() {
        #expect(RightPanelSection.allCases.count == 6)
        for section in RightPanelSection.allCases {
            #expect(!section.rawValue.isEmpty)
            #expect(!section.rawValue.contains(","))
        }
        // Порядок панели сверху вниз: гит, хромкаст, субагенты, терминал,
        // план, цель.
        #expect(RightPanelSection.allCases == [.git, .chromecast, .subagents, .terminal, .plan, .goal])
    }
}
