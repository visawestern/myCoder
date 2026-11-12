import Testing
import Foundation
@testable import myCoder

/// Шаги плана правой панели жили только в `AppState.stepsBySessionID`:
/// после перезапуска приложения у чата снова «Нет шагов», хотя чеклист уже
/// построен. Здесь сериализация шагов в `sessionMetadata` и обратно.
@MainActor
@Suite("Сохранение шагов чата в базе")
struct SessionStepsPersistenceLogicTests {

    @Test("Кодирование и декодирование сохраняют порядок, заголовки и статусы")
    func roundTripKeepsEverything() throws {
        let steps = [
            TaskStep(title: "Открыть браузер", status: .completed),
            TaskStep(title: "Починить WebGL", status: .inProgress),
            TaskStep(title: "Проверить воду", status: .waiting),
        ]
        let encoded = try #require(SessionStepsPersistenceLogic.encode(steps))
        let decoded = SessionStepsPersistenceLogic.decode(encoded)

        #expect(decoded.map(\.title) == steps.map(\.title))
        #expect(decoded.map(\.status) == steps.map(\.status))
    }

    @Test("Пустой список очищает сохранённые шаги")
    func emptyStepsEncodeToNil() {
        #expect(SessionStepsPersistenceLogic.encode([]) == nil)
    }

    @Test("Нет данных или мусор в колонке — пустой список, а не падение")
    func missingOrCorruptDataDecodesToEmpty() {
        #expect(SessionStepsPersistenceLogic.decode(nil).isEmpty)
        #expect(SessionStepsPersistenceLogic.decode("").isEmpty)
        #expect(SessionStepsPersistenceLogic.decode("not json").isEmpty)
        #expect(SessionStepsPersistenceLogic.decode("{\"steps\":42}").isEmpty)
    }

    @Test("Шаги переживают запись и чтение через базу программы")
    func databaseRoundTrip() throws {
        let db = DatabaseManager.shared
        let sessionID = "steps-\(UUID().uuidString)"
        try db.insertSession(
            id: sessionID,
            projectId: ChatSession.standaloneProjectKey,
            title: "steps test",
            directory: ChatSession.standaloneProjectKey
        )
        defer { try? db.deleteSession(id: sessionID) }

        let steps = [
            TaskStep(title: "шаг A", status: .completed),
            TaskStep(title: "шаг B", status: .inProgress),
        ]
        try db.setSessionSteps(
            sessionId: sessionID,
            stepsJSON: SessionStepsPersistenceLogic.encode(steps)
        )
        let raw = try db.getSessionSteps(sessionId: sessionID)
        let restored = SessionStepsPersistenceLogic.decode(raw)

        #expect(restored.map(\.title) == ["шаг A", "шаг B"])
        #expect(restored.map(\.status) == [.completed, .inProgress])
    }

    @Test("Повторное сохранение заменяет старый план, а nil очищает колонку")
    func overwriteAndClear() throws {
        let db = DatabaseManager.shared
        let sessionID = "steps-\(UUID().uuidString)"
        try db.insertSession(
            id: sessionID,
            projectId: ChatSession.standaloneProjectKey,
            title: "steps overwrite test",
            directory: ChatSession.standaloneProjectKey
        )
        defer { try? db.deleteSession(id: sessionID) }

        try db.setSessionSteps(
            sessionId: sessionID,
            stepsJSON: SessionStepsPersistenceLogic.encode([
                TaskStep(title: "старый шаг", status: .waiting)
            ])
        )
        try db.setSessionSteps(
            sessionId: sessionID,
            stepsJSON: SessionStepsPersistenceLogic.encode([
                TaskStep(title: "новый шаг", status: .completed)
            ])
        )
        #expect(SessionStepsPersistenceLogic.decode(
            try db.getSessionSteps(sessionId: sessionID)
        ).map(\.title) == ["новый шаг"])

        try db.setSessionSteps(sessionId: sessionID, stepsJSON: nil)
        #expect(try db.getSessionSteps(sessionId: sessionID) == nil)
    }
}
