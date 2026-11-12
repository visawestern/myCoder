import Testing
import Foundation
@testable import myCoder

/// A project-less chat lives on its history alone. The pack used to keep only
/// 12 turns, so the turn that created `aquarium_3d.html` fell out while the
/// chat still asked follow-up questions about it. The pack must keep at least
/// as many turns as the raw history cap (40).
@MainActor
@Suite("Пакет истории чата — глубина не меньше 40 ходов")
struct ChatHistoryPackTurnsTests {

    private func turns(_ count: Int) -> [ChatHistoryBuilder.Turn] {
        (0..<count).map { index in
            ChatHistoryBuilder.Turn(
                role: index % 2 == 0 ? "user" : "assistant",
                content: "шаг \(index): aquarium_3d.html",
                isFinished: true
            )
        }
    }

    @Test("Пакет без проекта сохраняет ход, который был 40 сообщений назад")
    func keepsAtLeastFortyTurns() throws {
        let pack = try #require(TurnContextCompiler.compileChatHistory(
            message: "продолжай",
            turns: turns(50)
        ))
        #expect(pack.text.contains("шаг 10:"),
                "фактически: ранний ход потерян — пакет обрезан меньше 40 ходов")
        #expect(pack.text.contains("шаг 49:"))
    }
}
