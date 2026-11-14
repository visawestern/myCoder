import Foundation
import Testing
@testable import myCoder

/// TDD для последнего пути исполнения инструментов (локальный текстовый
/// цикл MiMo Serve): деструктивная команда обязана получить ту же КРАСНУЮ
/// карточку, что и в web-драйвере/DirectOpenAI, а не молчаливый отказ.
@MainActor
@Suite("Destructive command approval — red card on the text-protocol loop")
struct DestructiveCommandApprovalLogicTests {

    @Test("Деструктивный вызов строит красный approval с точной командой")
    func destructiveCallBuildsRedApproval() {
        let call = WebToolCall(
            name: "run_command",
            arguments: ["command": "rsync -a --delete api/ prod:/srv/"]
        )
        let approval = DestructiveCommandApprovalLogic.approval(
            call: call, projectRoot: "/project"
        )
        #expect(approval?.isDestructive == true)
        #expect(approval?.tool == "run_command")
        #expect(approval?.message.contains("DESTRUCTIVE") == true)
        #expect(approval?.message.contains("rsync -a --delete") == true)
    }

    @Test("Обычные вызовы не получают красную карточку")
    func ordinaryCallsHaveNoRedApproval() {
        #expect(DestructiveCommandApprovalLogic.approval(
            call: WebToolCall(name: "run_command", arguments: ["command": "npm test"]),
            projectRoot: "/project"
        ) == nil)
        #expect(DestructiveCommandApprovalLogic.approval(
            call: WebToolCall(name: "write_file", arguments: ["path": "a.txt", "content": "x"]),
            projectRoot: "/project"
        ) == nil)
    }

    @Test("Отказ пользователя возвращает модели честный запрет")
    func denialMessageStopsRetries() {
        let message = DestructiveCommandApprovalLogic.denialMessage.lowercased()
        #expect(message.contains("denied"))
        #expect(message.contains("not executed"))
        #expect(message.contains("do not retry"))
    }
}
