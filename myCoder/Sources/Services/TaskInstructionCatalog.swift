import Foundation

/// Deterministic "how to do this kind of task" instructions picked by the
/// prompt text (owner design 2026-11-04: «сборщик контента подбирает
/// инструкции как правильно делать ту или иную задачу согласно промпту»).
///
/// The internal model's own instructions (`LocalQueryPlan.instructions`)
/// win when present; this catalog is the floor for turns without an
/// internal model, so guidance never disappears just because the planner
/// fell back. Bounded, deduped, no invention: every entry is a procedure,
/// never a claim about the codebase.
enum TaskInstructionCatalog {

    static let maxInstructions = 6

    /// Keyword classification of the request into the fixed intent
    /// vocabulary. Deterministic; unknown → `.other` (no instructions —
    /// inventing guidance for an unclear request is worse than none).
    static func intent(for message: String) -> LocalQueryIntent {
        let lower = message.lowercased()
        func has(_ cues: [String]) -> Bool { cues.contains { lower.contains($0) } }

        // Explain is checked before fix: "объясни почему падает" must not
        // become a fix task.
        if has(["объясни", "расскажи про", "расскажи как", "как работает",
                "почему происходит", "what is", "how does", "explain"]) {
            return .explain
        }
        if has(["рефактор", "отрефактор", "переделай", "перенеси", "перепиши",
                "замени", "переструктури", "refactor", "restructure",
                "migrate", "deprecate", "больше не нужен", "устарел"]) {
            return .refactor
        }
        // Fix beats test: "почини падающий тест" is a fix, "напиши тест" is not.
        if has(["исправ", "почин", "фикс", "баг", "падает", "ошибк", "не работает",
                "сломал", "fix", "bug", "broken", "crash", "fails", "failing"]) {
            return .fix
        }
        if has(["тест", "тесты", "покрой", "юнит-", "unit test", "add tests",
                "напиши тест", "тестир"]) {
            return .test
        }
        if has(["добав", "сделай новый", "новая функци", "реализуй", "внедри",
                "add ", "implement", "create a", "создай"]) {
            return .add
        }
        return .other
    }

    /// The procedures for the turn. Empty for `.other` — honest silence
    /// instead of generic filler.
    static func instructions(for intent: LocalQueryIntent, message: String) -> [String] {
        let core: [String]
        switch intent {
        case .fix:
            core = [
                "Сначала воспроизведи проблему тестом — красный тест до правок.",
                "Чини корень, а не симптом: найди место, где ломается инвариант, а не там, где оно видно.",
                "После правки прогони затронутые тесты; регрессию закрой новым тестом."
            ]
        case .refactor:
            core = [
                "Поведение не меняется: перед переносом зафиксируй текущее поведение тестами-страховкой.",
                "Пройди по каждой связи и зависимости изменяемого кода: обнови всех потребителей, прежде чем менять ядро.",
                "Проверь, не стал ли старый механизм мёртвым кодом: UI-разделы, настройки и документация, ссылающиеся на него, удали вместе с ним.",
                "Между шагами прогоняй затронутые тесты; в конце — полный selftest."
            ]
        case .test:
            core = [
                "Пиши тест раньше кода: сначала красный, потом реализация до зелёного.",
                "Покрой регрессию и граничные случаи; тест должен падать по причине, а не по таймауту.",
                "Не мокай то, что проверяешь; мок только для внешних границ."
            ]
        case .add:
            core = [
                "TDD: контракт-тест раньше реализации.",
                "Проведи новую функцию до конца: код, вызов из UI/настроек, реестр возможностей и документация должны узнать о ней.",
                "Не оставляй переключателей-заглушек: либо функция работает, либо её нет."
            ]
        case .explain:
            core = [
                "Отвечай по коду проекта, указывая файл и строку для каждого утверждения.",
                "Не выдумывай API и поведение: чего нет в коде — того нет в ответе."
            ]
        case .other:
            core = []
        }

        var result = core
        let lower = message.lowercased()

        // Subject extras — keyed to the project's real domains.
        if lower.contains("браузер") || lower.contains("browser") || lower.contains("сайт") || lower.contains("страниц") {
            result.append("Для веба используй browser_fetch (текст/скриншот/клик через движок), а не web_fetch, когда нужна живая страница.")
        }
        if lower.contains("хранил") || lower.contains("sqlite") || lower.contains("базу данных") || lower.contains("database") || lower.contains("модель данных") {
            result.append("При смене способа хранения пройди всех потребителей данных и формата: миграцию, чтения, записи и UI, который показывал старые сущности.")
        }
        if lower.contains("интерфейс") || lower.contains("ui") || lower.contains("экран") || lower.contains("view") || lower.contains("панель") {
            result.append("UI-правки проверяй вместе с состоянием: что произойдёт с экраном при пустых данных, ошибке и повторном входе.")
        }

        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }.prefix(maxInstructions).map { $0 }
    }
}
