import Foundation

/// Compacts chat history when it is added to a context pack.
///
/// User directive 2026-11-08: the history section must not be a raw dump of
/// full messages and answers ("тупо текст"). Instead it must be a compact
/// chain of the real theses — key and non-key — each tagged with its status
/// (done / not done) AS THE CHAT ITSELF STATES IT. The extractor never
/// invents facts: everything in the output is derived from the chat's own
/// words, so the "по версии чата" requirement holds by construction.
///
/// This is deterministic (no model, no network), so it keeps the compiler's
/// "deterministic by construction" invariant and is fully unit-testable.
enum HistoryCompactifier {

    /// The compacted history section body. Empty when there is nothing to
    /// compact (no user/assistant turns).
    static func compact(_ turns: [ChatHistoryBuilder.Turn]) -> String {
        let cleaned = turns.filter { $0.role == "user" || $0.role == "assistant" }
        guard !cleaned.isEmpty else { return "" }

        var lines: [String] = []
        let header = "История чата (сжатая, по версии чата; \(cleaned.count) ход\(plural(cleaned.count))):"
        lines.append(header)

        for (index, turn) in cleaned.enumerated() {
            let role = turn.role == "user" ? "Пользователь" : "Ассистент"
            lines.append("\(index + 1). [\(role)]")
            let theses = theses(in: turn.content, role: turn.role)
            if theses.isEmpty {
                lines.append("   - (без разборчивых тезисов)")
            } else {
                for thesis in theses {
                    lines.append("   - \(thesis.render())")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A single thesis line: `[статус][ключевость] текст`.
    /// Status is always present; keyness is tagged only when the thesis is key.
    struct Thesis {
        let text: String
        let status: Status
        let isKey: Bool

        /// One rendered thesis line: `[статус][ключевость] текст`.
        func render() -> String {
            let keyTag = isKey ? "[ключ.] " : ""
            return "[\(status.rawValue)] \(keyTag)\(text)"
        }
    }

    enum Status: String {
        case done = "сделано"
        case notDone = "не сделано"
        case open = "открытый вопрос"
    }

    /// Split a message into theses and classify each. A thesis is one
    /// sentence-ish segment.
    static func theses(in text: String, role: String) -> [Thesis] {
        let segments = splitSentences(text)
        var result: [Thesis] = []
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Drop pure greetings / acknowledgements unless they carry content.
            if isFiller(trimmed) { continue }
            let status = classify(trimmed, role: role)
            let isKey = isKeyThesis(trimmed)
            result.append(Thesis(text: trimmed, status: status, isKey: isKey))
        }
        return result
    }

    // MARK: - Segmentation

    /// Split into sentences on `.`, `!`, `?` followed by whitespace. Avoid
    /// splitting inside paths ("file.swift", "v1.2") and abbreviations.
    static func splitSentences(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var result: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            current.append(ch)
            var nextIndex = text.index(after: index)
            if ch == "." || ch == "!" || ch == "?" {
                // Don't split if the next char continues an identifier/abbrev
                // (e.g. "file.swift", "т.е.", "v1.2").
                if nextIndex < text.endIndex {
                    let next = text[nextIndex]
                    let isAbbrev = next.isLetter || next.isNumber || next == "_"
                    let isInToken = ch == "." && nextIndex < text.endIndex
                        && (next == "/" || next == "\\")
                    if isAbbrev || isInToken {
                        index = text.index(after: index)
                        continue
                    }
                }
            }
            // Commit when a sentence terminator is followed by whitespace/end.
            let isTerminator = ch == "." || ch == "!" || ch == "?"
            let atEnd = nextIndex >= text.endIndex
            let followedBySpace = nextIndex < text.endIndex && text[nextIndex].isWhitespace
            if isTerminator && (atEnd || followedBySpace) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { result.append(piece) }
                current = ""
                // skip trailing whitespace
                while nextIndex < text.endIndex && text[nextIndex].isWhitespace {
                    nextIndex = text.index(after: nextIndex)
                }
                index = nextIndex
                continue
            }
            index = text.index(after: index)
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    // MARK: - Status classification

    static let doneMarkers: [String] = [
        "сделано", "сделал", "сделала", "готово", "готова",
        "реализован", "реализована", "реализовано", "реализовал",
        "исправлен", "исправлена", "исправлено", "исправил", "исправила",
        "написал", "написала", "написан", "написана", "написано",
        "добавил", "добавила", "добавлен", "добавлена", "добавлено",
        "обновил", "обновила", "обновлён", "обновлена", "обновлено",
        "удалил", "удалила", "удалён", "удалена", "удалено",
        "переименовал", "переименован", "переименовано",
        "проверил", "проверила", "проверено", "проверен", "проверена",
        "запустил", "запустила", "запущен", "запущена", "запущено",
        "прошёл", "прошла", "прошли", "прошло", "прошел", "прошла",
        "выполнил", "выполнено", "выполнен", "выполнена",
        "закоммитил", "закоммител", "закоммичен", "закоммичено",
        "собрал", "собрано", "собран", "собрана", "собрано",
        "подключил", "подключено", "подключен", "подключена",
        "установил", "установлен", "установлена", "установлено",
        "создал", "создала", "создан", "создана", "создано",
        "заменил", "заменила", "заменён", "заменена", "заменено",
        "рефакторил", "рефакторен", "рефакторено",
        "протестировал", "протестировано", "протестирован",
        "покрыл", "покрыто", "покрыт", "покрыта",
        "смержил", "смержено", "смёржено", "смержен",
        "✅", "☑", "OK", "завершено", "завершён", "завершена",
        "implemented", "done", "completed", "fixed", "added", "updated"
    ]

    static let notDoneMarkers: [String] = [
        "нужно", "надо", "необходимо", "предстоит", "планирую", "планируем",
        "собираюсь", "собираемся", "собираюсь", "сначала", "затем", "потом",
        "далее", "ожидаю", "ожидаем", "подожди", "уточни", "уточните",
        "проверь", "проверьте", "сделай", "сделайте", "добавь", "добавьте",
        "исправь", "исправьте", "реализуй", "реализуйте", "выполни",
        "выполните", "запусти", "запустите", "попробуй", "попробуйте",
        "нужно будет", "надо будет", "обсудим", "обсудить", "тайм", "todo",
        "fixme", "TODO", "FIXME", "TBD", "WIP", "в процессе", "в работе",
        "продолжим", "продолжить", "дальше", "дальнейш", "следующий",
        "следующим", "следующ", "давай", "давайте", "хотел бы", "хотела бы",
        "хотелось бы", "было бы полезно", "стоит", "попробую", "попробуем",
        "v2", "вторая версия", "потом", "позже"
    ]

    static func classify(_ thesis: String, role: String) -> Status {
        let lower = thesis.lowercased()
        // A sentence that is itself a question is an open question.
        if thesis.trimmingCharacters(in: .whitespaces).hasSuffix("?")
            || lower.hasPrefix("вопрос") || lower.contains("уточни, пожалуйста") {
            return .open
        }
        // Done markers win unless a pending marker explicitly says otherwise
        // in the same sentence ("сделано, но ещё нужно …").
        let hasDone = doneMarkers.contains { lower.contains($0) }
        let hasNotDone = notDoneMarkers.contains { lower.contains($0) }
        if hasDone && !hasNotDone { return .done }
        if hasNotDone { return .notDone }
        if hasDone && hasNotDone { return .notDone }
        // Assistant turns that contain code blocks or explicit completion verbs
        // are treated as having done work; plain user asks are open.
        if role == "assistant" {
            if thesis.contains("```") || thesis.contains("`") {
                return .done
            }
            return .notDone
        }
        return .open
    }

    // MARK: - Keyness

    /// A thesis is key when it names a file, code identifier, tool, or a
    /// decision — things the next turn must not lose. Everything else
    /// (small talk, clarifications without decisions) is non-key.
    static func isKeyThesis(_ thesis: String) -> Bool {
        let lower = thesis.lowercased()
        if containsPath(thesis) { return true }
        if lower.contains("решили") || lower.contains("решил") || lower.contains("решила")
            || lower.contains("выбрали") || lower.contains("выбрал") || lower.contains("выбрала")
            || lower.contains("договорились") || lower.contains("итог") || lower.contains("вывод")
            || lower.contains("решение") || lower.contains("план") {
            return true
        }
        if containsCodeIdentifier(thesis) { return true }
        // Tool names mention.
        let toolHints = ["тест", "тест ", "тесты", "сборк", "коммит", "бренч",
                         "пул", "pr", "модель", "провайдер", "api", "эндпоинт",
                         "endpoint", "файл", "функци", "класс", "структур", "метод"]
        for hint in toolHints where lower.contains(hint) { return true }
        return false
    }

    static func containsPath(_ text: String) -> Bool {
        // A path-like token: letters/numbers/underscore followed by a dot and
        // extension, or containing "/" with a letter before it.
        let pattern = #"[A-Za-z0-9_./\-]+\.[A-Za-z0-9]{1,8}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = text as NSString
        return regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }

    static func containsCodeIdentifier(_ text: String) -> Bool {
        // Contains an identifier with an uppercase letter after a lowercase one
        // (camelCase) or an underscore — typical of code names.
        let pattern = #"[a-z][A-Z][A-Za-z0-9]*|[_][A-Za-z0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = text as NSString
        return regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }

    // MARK: - Filler

    static let fillerMarkers: [String] = [
        "привет", "здравствуй", "добрый день", "спасибо", "благодарю",
        "ок", "окей", "понятно", "понял", "поняла", "ясно", "угу",
        "хорошо", "отлично", "супер", "спс", "пожалуйста", "без проблем",
        "рад помочь", "рада помочь", "чем могу помочь", "как дела"
    ]

    static func isFiller(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.count <= 4 { return true }
        for marker in fillerMarkers where lower == marker || lower.hasPrefix(marker + " ") {
            return true
        }
        return false
    }

    private static func plural(_ n: Int) -> String {
        if n % 10 == 1 && n % 100 != 11 { return "" }
        if n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) { return "а" }
        return "ов"
    }
}
