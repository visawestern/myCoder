import Foundation

/// Безопасное кодирование строки в JS-литерал.
/// JSONSerialization не принимает String как top-level объект, поэтому
/// сериализуем массив и срезаем скобки: ["..."] → "..."
enum WebJSString {
    static func encode(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
