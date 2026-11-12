import Foundation

/// Сериализация шагов плана чата для колонки `sessions.metadata`.
///
/// `TaskStep` — UI-модель: `id` — случайный UUID, `Codable` не реализует.
/// Для восстановления панели нужны только заголовок и статус в исходном
/// порядке, поэтому хранится компактный снимок. Пустой список очищает
/// колонку (`nil`), чтобы у завершённого/очищенного чата не оставался
/// устаревший план.
enum SessionStepsPersistenceLogic {

    private struct Payload: Codable {
        var steps: [StoredStep]
    }

    private struct StoredStep: Codable {
        var title: String
        var status: String
    }

    /// Шаги → JSON для базы.
    ///
    /// Вход: `steps` — шаги плана чата.
    /// Выход: JSON-строка или nil для пустого списка/ошибки кодирования.
    /// Зависимости: `TaskStep`, `StepStatus`.
    static func encode(_ steps: [TaskStep]) -> String? {
        guard !steps.isEmpty else { return nil }
        let payload = Payload(steps: steps.map {
            StoredStep(title: $0.title, status: $0.status.rawValue)
        })
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// JSON из базы → шаги.
    ///
    /// Вход: `raw` — содержимое `sessions.metadata` или nil.
    /// Выход: шаги в сохранённом порядке; nil/пусто/мусор → пустой список.
    /// Зависимости: `TaskStep`, `StepStatus`.
    static func decode(_ raw: String?) -> [TaskStep] {
        guard let raw,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        return payload.steps.compactMap { stored in
            let title = stored.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return TaskStep(
                title: title,
                status: StepStatus(rawValue: stored.status) ?? .waiting
            )
        }
    }
}
