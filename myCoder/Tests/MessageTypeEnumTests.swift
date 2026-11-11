import Testing
@testable import myCoder

/// Связка типа сообщения и режима агента (build/plan/compose) + роли и
/// действия сообщения.
@MainActor
@Suite("MessageType и базовые перечисления сообщений")
struct MessageTypeEnumTests {

    @Test("MessageType ↔ AgentMode round-trip")
    func messageTypeAgentModeRoundTrip() {
        for mode in AgentMode.allCases {
            let type = MessageType(from: mode)
            #expect(type.toAgentMode == mode)
        }
        #expect(MessageType(from: .build) == .build)
        #expect(MessageType(from: .plan) == .plan)
        #expect(MessageType(from: .compose) == .compose)
    }

    @Test("Иконки режимов непустые и различны")
    func modeIcons() {
        #expect(!AgentMode.build.icon.isEmpty)
        #expect(!AgentMode.plan.icon.isEmpty)
        #expect(!AgentMode.compose.icon.isEmpty)
        #expect(AgentMode.build.icon != AgentMode.plan.icon)
    }

    @Test("MessageAction: raw значения")
    func messageActionRawValues() {
        #expect(MessageAction.wrote.rawValue == "Wrote")
        #expect(MessageAction.updated.rawValue == "Updated")
        #expect(MessageAction.ran.rawValue == "Ran")
        #expect(MessageAction.searched.rawValue == "Searched")
    }
}
