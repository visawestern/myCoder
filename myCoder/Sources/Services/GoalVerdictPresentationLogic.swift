import Foundation

/// Распознаёт сообщение, которое целиком является вердиктом проверки цели
/// (`{"complete":…,"notDone":[…],"reason":…}`), чтобы показать его чипом и
/// спойлером, а не сырым JSON (жалоба владельца 2026-11-09).
enum GoalVerdictPresentationLogic {

    struct Presentation: Equatable, Sendable {
        let complete: Bool
        let notDone: [String]
        let reason: String

        var title: String {
            complete ? "Цель выполнена" : "Цель не выполнена"
        }

        var subtitle: String {
            if complete { return "Проверка адвоката дьявола: замечаний нет" }
            let count = notDone.count
            return count == 1 ? "Не готов 1 пункт" : "Не готово пунктов: \(count)"
        }
    }

    /// Вердикт распознаётся только когда JSON — это ВСЁ сообщение
    /// (допускаются ```json-фенсы и пробелы). Иначе обычный ответ с
    /// упоминанием JSON не должен превращаться в чип.
    static func presentation(in text: String) -> Presentation? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        trimmed = strippingFences(trimmed)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
        guard let verdict = GoalVerdictParser.parse(trimmed), verdict.valid else { return nil }
        return Presentation(complete: verdict.complete,
                            notDone: verdict.notDone,
                            reason: verdict.reason)
    }

    private static func strippingFences(_ text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        var body = text
        if let firstNewline = body.firstIndex(of: "\n") {
            body = String(body[body.index(after: firstNewline)...])
        }
        if let closing = body.range(of: "```", options: .backwards) {
            body = String(body[..<closing.lowerBound])
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
