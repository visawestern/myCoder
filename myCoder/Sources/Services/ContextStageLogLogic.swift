import Foundation

/// One-line, honest progress text for context assembly (user directive
/// 2026-11-03, п.2): the composer shows exactly what is being read right now,
/// not a generic spinner label. Pure and deterministic, so it is testable
/// without the UI.
enum ContextStageLogLogic {

    enum Stage: String, CaseIterable, Sendable {
        case planning
        case index
        case memory
        case graph
        case skills
        case impact
        case files
    }

    /// The source each stage is reading. Kept short on purpose: the composer
    /// line is one line, and a long sentence gets truncated by the layout.
    static func line(for stage: Stage, detail: String = "") -> String {
        let base: String
        switch stage {
        case .planning:
            base = "Внутренняя модель выбирает файлы и символы"
        case .index:
            base = "Читаю индекс проекта"
        case .memory:
            base = "Загружаю память проекта и историю задачи"
        case .graph:
            base = "Строю граф кода: символы и связи"
        case .skills:
            base = "Подбираю скиллы под запрос"
        case .impact:
            base = "Проверяю связи и зависимости изменяемого кода"
        case .files:
            base = "Читаю выбранные файлы и собираю контекст"
        }
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return "\(base) · \(trimmed)"
    }

    /// Final line after the pack is built. It states what actually made it in,
    /// so a pack with nothing in it is never presented as a full one.
    static func doneLine(fileCount: Int, memoryCount: Int, hasGraph: Bool,
                         hasImpact: Bool = false) -> String {
        var parts: [String] = []
        if fileCount > 0 { parts.append("файлов: \(fileCount)") }
        if memoryCount > 0 { parts.append("память: \(memoryCount)") }
        if hasGraph { parts.append("граф: да") }
        if hasImpact { parts.append("связи: да") }
        guard !parts.isEmpty else { return "Контекст собран без источников" }
        return "Контекст собран: " + parts.joined(separator: ", ")
    }
}
