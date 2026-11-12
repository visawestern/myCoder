import Testing
import Foundation
@testable import myCoder

/// Presentation logic for the ЦЕЛЬ card in the right sidebar. Pure, so the
/// status/progress/action rules are verified without rendering SwiftUI.
@MainActor
@Suite("ЦЕЛЬ — представление карточки")
struct GoalPresentationTests {

    private func goal(state: UserGoal.State,
                      plan: [UserGoal.PlanItem] = []) -> UserGoal {
        UserGoal(title: "Цель", plan: plan, state: state)
    }

    @Test("Прогресс считается по выполненным шагам")
    func progress() {
        let plan = [
            UserGoal.PlanItem(title: "a", status: .done),
            UserGoal.PlanItem(title: "b", status: .inProgress),
            UserGoal.PlanItem(title: "c", status: .todo),
            UserGoal.PlanItem(title: "d", status: .done)
        ]
        let p = GoalPresentation(goal: goal(state: .active, plan: plan))
        #expect(p.doneCount == 2)
        #expect(p.totalCount == 4)
        #expect(abs(p.progress - 0.5) < 0.0001)
    }

    @Test("Пустой план: прогресс 0 и показывается подсказка вместо прогресс-бара")
    func emptyPlan() {
        let p = GoalPresentation(goal: goal(state: .pending))
        #expect(p.progress == 0)
        #expect(p.showsProgress == false)
        #expect(p.showsPlanHint == true)
        #expect(p.showsPlanDisclosure == false)
    }

    @Test("Есть план: показываются прогресс и спойлер шагов")
    func planPresent() {
        let plan = [UserGoal.PlanItem(title: "a", status: .todo)]
        let p = GoalPresentation(goal: goal(state: .active, plan: plan))
        #expect(p.showsProgress == true)
        #expect(p.showsPlanHint == false)
        #expect(p.showsPlanDisclosure == true)
    }

    @Test("Главное действие зависит от состояния цели")
    func primaryAction() {
        #expect(GoalPresentation(goal: goal(state: .pending)).primaryAction == .start)
        #expect(GoalPresentation(goal: goal(state: .active)).primaryAction == .pause)
        #expect(GoalPresentation(goal: goal(state: .paused)).primaryAction == .resume)
        #expect(GoalPresentation(goal: goal(state: .error)).primaryAction == .resume)
        #expect(GoalPresentation(goal: goal(state: .done)).primaryAction == .none)
    }

    @Test("Статус и цвет зависят от состояния цели")
    func statusAndColor() {
        #expect(GoalPresentation(goal: goal(state: .active)).stateLabel == .locGoalRunning)
        #expect(GoalPresentation(goal: goal(state: .active)).stateColor == .brand)
        #expect(GoalPresentation(goal: goal(state: .paused)).stateLabel == .locGoalPaused)
        #expect(GoalPresentation(goal: goal(state: .paused)).stateColor == .warning)
        #expect(GoalPresentation(goal: goal(state: .error)).stateLabel == .locGoalError)
        #expect(GoalPresentation(goal: goal(state: .error)).stateColor == .error)
        #expect(GoalPresentation(goal: goal(state: .done)).stateLabel == .locGoalDone)
        #expect(GoalPresentation(goal: goal(state: .done)).stateColor == .success)
        #expect(GoalPresentation(goal: goal(state: .pending)).stateLabel == .locGoalCreated)
        #expect(GoalPresentation(goal: goal(state: .pending)).stateColor == .muted)
    }

    @Test("Цель выполнена: главного действия нет, удаление остаётся доступным")
    func doneGoal() {
        let p = GoalPresentation(goal: goal(state: .done))
        #expect(p.primaryAction == .none)
        #expect(p.isComplete == true)
    }

    @Test("Управление сессией цели доступно по состоянию")
    func sessionControlsAvailability() {
        let pending = GoalPresentation(goal: goal(state: .pending))
        #expect(pending.canStart)
        #expect(!pending.canPause)
        #expect(!pending.canStop)

        let active = GoalPresentation(goal: goal(state: .active))
        #expect(!active.canStart)
        #expect(active.canPause)
        #expect(active.canStop)

        let paused = GoalPresentation(goal: goal(state: .paused))
        #expect(paused.canStart)
        #expect(!paused.canPause)
        #expect(!paused.canStop)

        let failed = GoalPresentation(goal: goal(state: .error))
        #expect(failed.canStart)
        #expect(!failed.canPause)
        #expect(!failed.canStop)

        let done = GoalPresentation(goal: goal(state: .done))
        #expect(!done.canStart)
        #expect(!done.canPause)
        #expect(!done.canStop)
    }
}
