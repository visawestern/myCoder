import Foundation

/// Модели системы полноценного отката диалога (rollback). Все типы —
/// чистые value-типы, без зависимости от UI и хранилищ, чтобы планирование
/// и отчётность были тестируемы без I/O.

/// Минимальное представление сообщения чата для планирования отката.
struct RollbackMessageRef: Equatable, Sendable, Codable {
    let id: String
    let createdAt: Double
    let role: String
    let content: String
}

/// Запись undo-стека (снапшот до изменения) для планирования отката.
struct RollbackUndoEntryRef: Equatable, Sendable, Codable {
    let id: String
    let path: String
    let snapshotID: String?
    let actionType: String
    let canUndo: Bool
    let createdAt: Double
    /// Номер сообщения модели, во время которого сделана правка. nil — старая
    /// запись без привязки; для неё остаётся сравнение по времени.
    let messageID: String?

    init(id: String, path: String, snapshotID: String?, actionType: String,
         canUndo: Bool, createdAt: Double, messageID: String? = nil) {
        self.id = id
        self.path = path
        self.snapshotID = snapshotID
        self.actionType = actionType
        self.canUndo = canUndo
        self.createdAt = createdAt
        self.messageID = messageID
    }
}

/// Необратимое действие агента (например, run_command), случившееся после
/// целевого запроса. Привязка к сообщению позволяет вычислить границу
/// безопасного отката.
struct IrreversibleAgentAction: Equatable, Sendable, Codable {
    let messageID: String
    let toolName: String
}

/// Статус шага отката.
enum RollbackStepStatus: String, Sendable, Equatable, Codable {
    case done
    case blocked
}

/// Один шаг отката: либо восстановление файла из снапшота, либо
/// блокировка (необратимое действие / потерянный снапшот).
struct RollbackStep: Equatable, Sendable, Codable {
    let entryID: String?
    let snapshotID: String?
    let path: String
    let actionType: String
    let status: RollbackStepStatus
    let reason: String?
}

/// План отката диалога к целевому запросу.
struct RollbackPlan: Equatable, Sendable, Codable {
    let targetMessageID: String

    /// true — откат полный (можно вернуть состояние ровно к моменту запроса).
    let full: Bool

    /// Шаги отката (выполняемые и заблокированные).
    let steps: [RollbackStep]

    /// ID последнего ВИДИМОГО сообщения после урезания диалога. При полном
    /// откате — сам целевой запрос; при частичном — сообщение перед первым
    /// необратимым барьером.
    let visibilityCutMessageID: String?

    /// Причина, почему дальше откатить нельзя (при частичном откате).
    let stopReason: String?

    /// При полном откате последнего запроса — текст, который нужно вернуть
    /// в окно ввода промпта (сам запрос исчезает из чата).
    let promptRestore: String?
}

/// Дифф файла для наглядного показа (стиль VSCode: до/после).
struct RollbackFileDiff: Equatable, Sendable, Codable {
    let path: String
    let before: String
    let after: String
}

/// Стадия отката для отчёта (что делали и как получилось).
struct RollbackStage: Equatable, Sendable, Codable {
    let title: String
    let success: Bool
    let detail: String
}

/// Полный отчёт об откате — данные для чипа и диалога.
struct RollbackReport: Equatable, Sendable, Codable {
    let plan: RollbackPlan
    let stages: [RollbackStage]
    let diffs: [RollbackFileDiff]
    /// Финальная ошибка, если откат завершился сбоем.
    let error: String?
}

/// Данные оранжевого чипа отката в чате.
struct RollbackChipData: Equatable, Sendable, Codable {
    let createdAt: Date
    let full: Bool
    let summary: String
    let report: RollbackReport
}

/// Вердикт внутренней модели-аудитора отката.
struct RollbackVerdict: Equatable, Sendable, Codable {
    let canRollback: Bool
    let irreversible: [String]
    let stopAtMessageID: String?
    let valid: Bool
}

/// Кодирование/декодирование данных чипа отката в текст системного
/// сообщения: `[ROLLBACK_CHIP]\n<JSON>`. Чистая функция, покрыта тестами.
enum RollbackChipCodec {

    static let marker = "[ROLLBACK_CHIP]"

    static func encode(_ data: RollbackChipData) -> String? {
        guard let json = try? JSONEncoder().encode(data),
              let text = String(data: json, encoding: .utf8) else { return nil }
        return marker + "\n" + text
    }

    static func decode(from content: String) -> RollbackChipData? {
        guard content.hasPrefix(marker) else { return nil }
        let body = content.dropFirst(marker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = body.data(using: .utf8),
              let chip = try? JSONDecoder().decode(RollbackChipData.self, from: data) else {
            return nil
        }
        return chip
    }
}
