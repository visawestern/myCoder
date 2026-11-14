import Foundation
import Testing
@testable import myCoder

/// Финализация цели: после завершения обычной цели автоматически создаётся
/// и запускается итоговая проверка плана; по завершении итоговой цели
/// работа с целями останавливается полностью (директива 2026-11-14).
@Suite("Итоговая цель после завершения обычной")
struct GoalFinalizationLogicTests {

    private func completedGoal(isFinal: Bool = false,
                               project: String? = "/p",
                               chat: String? = "chat-a") -> UserGoal {
        UserGoal(
            title: "Обычная цель",
            plan: [],
            state: .done,
            isFinal: isFinal,
            projectPath: project,
            chatID: chat
        )
    }

    @Test("Обычная цель запускает итоговую проверку")
    func shouldStartFinalForRegularGoal() {
        #expect(GoalFinalizationLogic.shouldStartFinal(goal: completedGoal(isFinal: false)))
    }

    @Test("Итоговая цель не запускает ещё одну проверку")
    func shouldNotStartFinalForFinalGoal() {
        #expect(!GoalFinalizationLogic.shouldStartFinal(goal: completedGoal(isFinal: true)))
    }

    @Test("Итоговая цель имеет фиксированный текст и флаг isFinal")
    func finalGoalCarriesDirectiveText() {
        let goal = GoalFinalizationLogic.finalGoal(
            for: completedGoal(),
            context: GoalContext()
        )
        #expect(goal.isFinal)
        #expect(goal.state == .pending)
        #expect(goal.title == GoalFinalizationLogic.finalGoalTitle)
        #expect(goal.title.contains("адвокат дьявола"))
        #expect(goal.title.contains("95 из 100"))
    }

    @Test("Итоговая цель наследует скоуп завершённой цели")
    func finalGoalInheritsScope() {
        let goal = GoalFinalizationLogic.finalGoal(
            for: completedGoal(project: "/proj", chat: "chat-7"),
            context: GoalContext(chatID: "other", projectPath: "/other")
        )
        #expect(goal.projectPath == "/proj")
        #expect(goal.chatID == "chat-7")
    }

    @Test("Пустой скоуп цели добирается из контекста")
    func finalGoalUsesContextFallback() {
        let goal = GoalFinalizationLogic.finalGoal(
            for: completedGoal(project: nil, chat: nil),
            context: GoalContext(chatID: "fallback-chat", projectPath: "/fallback")
        )
        #expect(goal.projectPath == "/fallback")
        #expect(goal.chatID == "fallback-chat")
    }

    @Test("UserGoal кодируется и декодируется с флагом isFinal")
    func finalFlagSurvivesCodableRoundTrip() throws {
        let goal = completedGoal(isFinal: true)
        let data = try JSONEncoder().encode(goal)
        let decoded = try JSONDecoder().decode(UserGoal.self, from: data)
        #expect(decoded.isFinal)
        #expect(decoded.title == goal.title)
    }

    @Test("Старые сохранённые цели без флага читаются как обычные")
    func legacyGoalDefaultsToRegular() throws {
        let legacy = completedGoal(isFinal: false)
        let data = try JSONEncoder().encode(legacy)
        // Имитация старого формата: без ключа isFinal.
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var stripped = json
        stripped.removeValue(forKey: "isFinal")
        let strippedData = try JSONSerialization.data(withJSONObject: stripped)
        let decoded = try JSONDecoder().decode(UserGoal.self, from: strippedData)
        #expect(!decoded.isFinal)
    }
}
