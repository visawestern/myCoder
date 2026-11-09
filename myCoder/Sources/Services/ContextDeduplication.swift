import Foundation

/// Дедупликация собранного контекста перед отправкой модели.
///
/// Живой дефект 2026-11-09: в пакете оказывались два блока одного и того же
/// файла (кандидат + «зависимость» с другим символом), а фрагменты из истории
/// чата повторяли уже включённый код. Модель получала раздутый пакет, где
/// один и тот же смысл оплачивался дважды.
enum ContextDeduplication {

    struct Result: Equatable {
        let sections: [ContextSection]
        let dropped: [DroppedSource]
    }

    /// Секция запроса неприкосновенна: слова пользователя не выкидываются
    /// даже если совпали с чем-то ещё.
    static let protectedTitles: Set<String> = ["Запрос"]

    static func deduplicate(_ sections: [ContextSection]) -> Result {
        var kept: [ContextSection] = []
        var keptBodies: [String] = []
        var keptPaths: Set<String> = []
        var dropped: [DroppedSource] = []

        // Строки кода, уже вошедшие в файловые блоки: повествовательные
        // секции (история, память) не должны повторять их ещё раз.
        var fileLines: Set<String> = []
        for section in sections where filePath(in: section) != nil {
            for line in section.body.components(separatedBy: "\n") {
                let normalized = normalize(line)
                guard normalized.count >= 60 else { continue }
                fileLines.insert(normalized)
                // Материализатор нумерует строки кода («42 | let x = …»), а
                // диалог цитирует ту же строку без номера. Запоминаем и
                // форму без номера, иначе дубль «из диалога и из файлов»
                // не находится.
                if let stripped = stripLineNumberPrefix(from: normalized) {
                    fileLines.insert(stripped)
                }
            }
        }

        for section in sections {
            if protectedTitles.contains(section.title) {
                kept.append(section)
                keptBodies.append(normalize(section.body))
                continue
            }

            var body = section.body
            var title = section.title
            if filePath(in: section) == nil, !fileLines.isEmpty {
                // Убираем из повествования строки, которые дословно уже есть
                // в файловых блоках: это тот самый дубль «из диалога и из файлов».
                let filtered = body.components(separatedBy: "\n").filter { line in
                    let normalized = normalize(line)
                    guard normalized.count >= 60 else { return true }
                    // Строка может быть в истории с префиксом («- [done] …»),
                    // поэтому проверяем вхождение, а не точное равенство.
                    return !fileLines.contains { normalized.contains($0) }
                }
                let cleaned = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty, !normalize(body).isEmpty {
                    dropped.append(DroppedSource(path: title, reason: "дубликат содержимого из файлов"))
                    continue
                }
                body = cleaned
            }

            let normalized = normalize(body)
            // 1. Точный дубль содержимого.
            if !normalized.isEmpty, keptBodies.contains(normalized) {
                dropped.append(DroppedSource(path: title, reason: "дубликат содержимого"))
                continue
            }

            // 2. Один блок на файл: кандидат и «зависимость» одного пути
            //    больше не дублируют друг друга.
            if let path = filePath(in: section) {
                if keptPaths.contains(path) {
                    dropped.append(DroppedSource(path: path, reason: "дубликат файла: уже включён"))
                    continue
                }
                keptPaths.insert(path)
            }

            // 3. Смысловой дубль в повествовательных секциях (память/история/
            //    скиллы). Файловые блоки сюда не попадают — у них своё правило.
            if filePath(in: section) == nil, normalized.count >= 240 {
                // Полное вхождение — самый частый случай: одна секция целиком
                // повторяет текст другой (память vs история, скилл vs инструкции).
                let contained = keptBodies.contains { other in
                    other.count >= 240 && (other.contains(normalized) || normalized.contains(other))
                }
                if contained || keptBodies.contains(where: { similarity($0, normalized) >= 0.85 }) {
                    dropped.append(DroppedSource(path: title, reason: "смысловой дубликат"))
                    continue
                }
            }

            kept.append(ContextSection(title: title, body: body))
            keptBodies.append(normalized)
        }
        return Result(sections: kept, dropped: dropped)
    }

    /// Путь файлового блока (`path` или `path — зависимость`); nil для
    /// повествовательных секций.
    static func filePath(in section: ContextSection) -> String? {
        guard section.body.hasPrefix("````") else { return nil }
        let suffix = " — зависимость"
        var title = section.title
        if title.hasSuffix(suffix) { title = String(title.dropLast(suffix.count)) }
        guard title.contains("/") || title.contains(".") else { return nil }
        return title
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Снимает префикс «123 | » с нормализованной строки кода. Возвращает nil,
    /// если строка не похожа на нумерованный блок материализатора — тогда
    /// строка используется как есть.
    static func stripLineNumberPrefix(from normalized: String) -> String? {
        guard let space = normalized.firstIndex(of: " ") else { return nil }
        let prefix = normalized[..<space]
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }) else { return nil }
        let rest = normalized[normalized.index(after: space)...]
        guard rest.hasPrefix("| ") else { return nil }
        let stripped = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    /// Jaccard по 4-словным шинглам. Набор ограничен, чтобы не гонять десятки
    /// тысяч пересечений на каждый ход.
    static func similarity(_ a: String, _ b: String, maxShingles: Int = 400) -> Double {
        let left = shingles(a, max: maxShingles)
        let right = shingles(b, max: maxShingles)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private static func shingles(_ text: String, max: Int) -> Set<String> {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 4 else { return Set(words.map(String.init)) }
        var result = Set<String>()
        for index in 0...(words.count - 4) {
            result.insert(words[index..<(index + 4)].joined(separator: " "))
            if result.count >= max { break }
        }
        return result
    }
}
