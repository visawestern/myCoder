import Foundation
import Testing
@testable import myCoder

/// User directive 2026-11-03 (п.1): the internal model is the component that
/// turns the user's words into a plan for context assembly. It must take part
/// by default — an opt-in switch meant it never ran, and every pack silently
/// fell back to the deterministic plan.
@MainActor
@Suite("Внутренняя модель: участие по умолчанию")
struct LocalPlannerSettingsTests {

    private func freshDefaults() -> UserDefaults {
        let name = "LocalPlannerSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Планировщик включён по умолчанию")
    func enabledByDefault() {
        #expect(LocalPlannerSettings.defaultEnabled)
        #expect(LocalPlannerSettings.isEnabled(in: freshDefaults()))
    }

    @Test("Явное выключение пользователем сохраняется")
    func explicitDisableWins() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: LocalPlannerSettings.storageKey)
        #expect(!LocalPlannerSettings.isEnabled(in: defaults))
    }

    @Test("Явное включение сохраняется")
    func explicitEnableWins() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: LocalPlannerSettings.storageKey)
        #expect(LocalPlannerSettings.isEnabled(in: defaults))
    }

    @Test("Без назначенной внутренней модели пакет честно называет причину")
    func missingInternalModelIsNamedHonestly() async {
        let result = await InternalContextPlanner.plan(
            message: "переделай хранение кадров",
            context: LocalPlannerContext(entities: [], memoryTags: []),
            complete: { _ in throw InternalModelRunner.NoModelError() }
        )
        guard case .fallback(let reason) = result.status else {
            Issue.record("ожидался fallback, получено \(result.status)")
            return
        }
        #expect(reason.lowercased().contains("внутренняя модель не назначена"))
        #expect(result.plan == nil)
    }

    @Test("Таймаут внутренней модели — видимый fallback, а не пустой план")
    func timeoutIsVisibleFallback() async {
        let result = await InternalContextPlanner.plan(
            message: "вопрос",
            context: LocalPlannerContext(entities: [], memoryTags: []),
            budget: 0.05,
            complete: { _ in
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "{}"
            }
        )
        guard case .fallback = result.status else {
            Issue.record("ожидался fallback по таймауту")
            return
        }
    }

    @Test("Пустой ответ внутренней модели — fallback, а не выдуманный план")
    func emptyPlanIsFallback() async {
        let result = await InternalContextPlanner.plan(
            message: "вопрос",
            context: LocalPlannerContext(entities: [], memoryTags: []),
            complete: { _ in #"{"intent":"other","terms":[],"symbols":[],"files":[],"memoryTags":[]}"# }
        )
        guard case .fallback = result.status else {
            Issue.record("ожидался fallback на пустом плане")
            return
        }
    }
}
