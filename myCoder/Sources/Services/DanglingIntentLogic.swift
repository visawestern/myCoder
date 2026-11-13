import Foundation

/// Detects a dangling intent: the model's prose announces that it is about to
/// perform work, but the response contains no tool call, so nothing ran and
/// the turn would end with a promise instead of a result (live evidence
/// 2026-11-13: a 672-char plan ending "Проверю счётчики ресурсов в JS." was
/// accepted as the final answer).
///
/// Pure text logic: no UI, no browser, no I/O. The driver calls it only for a
/// response that parsed to zero tool calls, below the iteration ceiling.
enum DanglingIntentLogic {

    /// Message sent to the model after a dangling intent is detected.
    /// Input: none. Output: one compact instruction that forbids narration
    /// and asks for the actual tool block. Dependencies: none.
    static let nudgeMessage = """
    Your previous message announced an action but contained no tool block, so nothing was executed. Do not narrate the next step: emit the tool call for the announced action now in the exact taught format, then wait for its result.
    """

    /// Whether the response announces an action that should have been a call.
    /// Input: the model's response text. Output: true when at least one prose
    /// sentence announces a first-person immediate/future work action.
    /// Dependencies: the Russian/English action vocabularies below.
    ///
    /// Deliberately conservative: results, questions, negations, offers,
    /// instructions addressed to the user and code samples never trigger it,
    /// because a false nudge burns a turn and confuses the model.
    static func announcesAction(_ text: String) -> Bool {
        let prose = strippingFencedCode(from: text)
        for sentence in sentences(in: prose) {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasSuffix("?") else { continue }
            if isOfferOrConditional(trimmed) { continue }
            if containsRussianAction(trimmed) || containsEnglishAction(trimmed) {
                return true
            }
        }
        return false
    }

    // MARK: - Text preparation

    /// Remove fenced code so future-tense comments in a sample never count.
    /// Input: raw response. Output: prose lines only. Dependencies: none.
    private static func strippingFencedCode(from text: String) -> String {
        var insideFence = false
        var kept: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                insideFence.toggle()
                continue
            }
            if !insideFence { kept.append(String(line)) }
        }
        return kept.joined(separator: "\n")
    }

    /// Split prose into sentences, keeping the terminator so a question mark
    /// remains visible to the caller. Input: prose. Output: sentence strings.
    /// Dependencies: NSRegularExpression (ICU).
    private static func sentences(in text: String) -> [String] {
        let pattern = #"[^.!?\n]+[.!?]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let scanner = text as NSString
        return regex
            .matches(in: text, range: NSRange(location: 0, length: scanner.length))
            .map { scanner.substring(with: $0.range) }
    }

    /// Whether the sentence is an offer or a conditional promise rather than
    /// an immediate action. Input: one sentence. Output: true to skip it.
    /// Dependencies: none.
    private static func isOfferOrConditional(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        let markers = [
            "if needed", "if you want", "if you'd like", "if you would like",
            "если нужно", "если хотите", "если потребуется", "при необходимости",
            "могу ", "могла ", "могли ", "could ", "would ", "might ", "should "
        ]
        return markers.contains { lower.contains($0) }
    }

    // MARK: - Russian

    /// First-person immediate/future forms of work verbs. Past tense
    /// ("проверил") and infinitives ("проверить") are intentionally absent.
    private static let russianActions = [
        "проверю", "проверяю", "проверяем", "проверим",
        "запущу", "запускаю", "запускаем", "запустим",
        "перезапущу", "перезапускаю", "перезапускаем",
        "исправлю", "исправляю", "исправляем", "исправим",
        "поправлю", "поправляю", "поправляем",
        "добавлю", "добавляю", "добавляем", "добавим",
        "обновлю", "обновляю", "обновляем", "обновим",
        "посмотрю", "смотрю", "смотрим", "гляну", "взгляну",
        "найду", "ищу", "ищем",
        "сделаю", "делаю", "делаем",
        "создам", "создаю", "создаём", "создаем", "создадим",
        "изменю", "меняю", "меняем", "изменим",
        "прочитаю", "читаю", "читаем",
        "открою", "открываю", "открываем",
        "выполню", "выполняю", "выполняем",
        "соберу", "собираю", "собираем",
        "протестирую", "тестирую", "тестируем",
        "продолжу", "продолжаю", "продолжаем",
        "перейду", "перехожу", "переходим",
        "проанализирую", "анализирую", "анализируем",
        "изучу", "изучаю", "изучаем",
        "сравню", "сравниваю", "сравниваем",
        "удалю", "удаляю", "удаляем",
        "перемещу", "перемещаю", "перемещаем",
        "скопирую", "копирую", "копируем",
        "сохраню", "сохраняю", "сохраняем",
        "установлю", "устанавливаю", "устанавливаем",
        "настрою", "настраиваю", "настраиваем",
        "починю", "чиню", "чиним",
        "перепишу", "переписываю", "переписываем",
        "отредактирую", "редактирую", "редактируем",
        "вставлю", "вставляю", "вставляем",
        "заменю", "заменяю", "заменяем",
        "допишу", "дописываю", "дописываем",
        "доделаю", "доделываю", "доделываем",
        "напишу", "пишу", "пишем",
        "сгенерирую", "генерирую", "генерируем",
        "отправлю", "отправляю", "отправляем",
        "загружу", "загружаю", "загружаем",
        "скачаю", "скачиваю", "скачиваем",
        "подключу", "подключаю", "подключаем",
        "включу", "включаю", "включаем",
        "выключу", "выключаю", "выключаем",
        "уберу", "убираю", "убираем",
        "улучшу", "улучшаю", "улучшаем",
        "выдам", "выдаю", "выдаём", "выдаем",
    ]

    /// Match a first-person work verb, skipping a negated occurrence.
    /// Input: one sentence. Output: true when an un-negated verb is present.
    /// Dependencies: `russianActions`.
    private static func containsRussianAction(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        let alternation = russianActions.joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![а-яa-z])(?:\(alternation))(?![а-яa-z])"
        ) else { return false }
        let scanner = lower as NSString
        for match in regex.matches(
            in: lower,
            range: NSRange(location: 0, length: scanner.length)
        ) {
            let prefixStart = max(0, match.range.location - 16)
            let prefix = scanner.substring(
                with: NSRange(location: prefixStart, length: match.range.location - prefixStart)
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            // "не проверю", "я не проверю", "больше не проверю".
            if prefix.hasSuffix("не") { continue }
            return true
        }
        return false
    }

    // MARK: - English

    /// Work verbs used after "let me", "I'll", "I'm going to".
    private static let englishVerbs = [
        "check", "run", "fix", "add", "update", "look", "find", "make",
        "create", "change", "read", "open", "execute", "build", "test",
        "continue", "move", "analyze", "analyse", "inspect", "compare",
        "delete", "copy", "save", "install", "configure", "rewrite", "edit",
        "replace", "verify", "validate", "search", "grep", "scan", "patch",
        "refactor", "restart", "write", "generate", "download", "upload",
        "connect", "enable", "disable", "remove", "clean", "improve",
        "render", "compile", "debug", "profile", "measure", "trace",
        "investigate",
    ]

    /// Present-continuous forms paired with "I'm".
    private static let englishGerunds = [
        "checking", "running", "fixing", "adding", "updating", "looking",
        "finding", "making", "creating", "changing", "reading", "opening",
        "executing", "building", "testing", "continuing", "moving",
        "analyzing", "analysing", "inspecting", "comparing", "deleting",
        "copying", "saving", "installing", "configuring", "rewriting",
        "editing", "replacing", "verifying", "validating", "searching",
        "scanning", "patching", "refactoring", "restarting", "writing",
        "generating", "downloading", "uploading", "connecting", "enabling",
        "disabling", "removing", "cleaning", "improving", "rendering",
        "compiling", "debugging", "profiling", "measuring", "tracing",
        "investigating",
    ]

    /// Match English future/intent or present-continuous work announcements.
    /// Input: one sentence. Output: true when one is present.
    /// Dependencies: `englishVerbs`, `englishGerunds`.
    private static func containsEnglishAction(_ sentence: String) -> Bool {
        let lower = sentence
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
        let verbs = englishVerbs.joined(separator: "|")
        let gerunds = englishGerunds.joined(separator: "|")
        let patterns = [
            #"\b(?:let me|i'll|i will|i'm going to|i am going to)\s+(?:\#(verbs))\b"#,
            #"\b(?:i'm|i am)\s+(?:\#(gerunds))\b"#,
        ]
        return patterns.contains { pattern in
            lower.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
