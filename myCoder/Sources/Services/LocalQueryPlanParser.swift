import Foundation
import os

/// Why a plan was rejected. Every case ends in fallback, never in a partially
/// applied plan: a half-trusted answer is worse than the deterministic one.
enum LocalQueryPlanError: Error, Equatable, LocalizedError {
    case notJSON
    case notAnObject
    case tooManyItems(field: String)
    case valueTooLong(field: String)
    case codeDetected(field: String)
    case lineNumberDetected(field: String)
    case wrongType(field: String)

    var errorDescription: String? {
        switch self {
        case .notJSON: return "no JSON object in the answer"
        case .notAnObject: return "the answer is not a JSON object"
        case .tooManyItems(let field): return "too many items in \(field)"
        case .valueTooLong(let field): return "a value in \(field) is too long"
        case .codeDetected(let field): return "code found in \(field)"
        case .lineNumberDetected(let field): return "line number found in \(field)"
        case .wrongType(let field): return "wrong type in \(field)"
        }
    }
}

/// Parses and validates the planner answer.
///
/// Validation is the safety boundary: a plan that contains a code snippet or a
/// `file:line` reference is rejected as a whole, because accepting the rest
/// would make the host act on an answer that did not follow the contract.
enum LocalQueryPlanParser {

    static let maxItemsPerField = 20
    static let maxValueLength = 80
    static let maxQuestions = 8
    static let maxQuestionLength = 400
    static let maxInstructions = 8
    static let maxInstructionLength = 400

    private static let lineReference = try? NSRegularExpression(pattern: #":\d{1,6}\b"#)
    /// Characters that do not belong in a name, a term or a tag.
    private static let codeCharacters: Set<Character> = [
        "{", "}", "(", ")", ";", "=", "<", ">", "*", "`", "\\", "\"", "'"
    ]

    static func parse(_ raw: String) throws -> LocalQueryPlan {
        guard let json = extractJSONObject(from: raw) else {
            throw LocalQueryPlanError.notJSON
        }
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalQueryPlanError.notAnObject
        }

        let intent = LocalQueryIntent.normalized(string(object["intent"]) ?? "")
        let terms = try strings(object, keys: ["terms"], field: "terms")
        let symbols = try strings(object, keys: ["symbols"], field: "symbols")
        let files = try strings(object, keys: ["files"], field: "files")
        let tags = try strings(object, keys: ["memory_tags", "memoryTags"], field: "memory_tags")
        let questions = try strings(object, keys: ["questions"], field: "questions")
        let skills = try strings(object, keys: ["skills"], field: "skills")
        let instructions = try strings(object, keys: ["instructions"], field: "instructions")

        return LocalQueryPlan(
            intent: intent,
            terms: dedupe(terms.map { $0.lowercased() }),
            symbols: dedupe(symbols),
            files: dedupe(files),
            memoryTags: dedupe(tags.map { $0.lowercased() }),
            questions: dedupe(questions),
            skills: dedupe(skills),
            instructions: dedupe(instructions)
        )
    }

    /// Keeps only entities that really exist in the bounded context. Unknown
    /// ones are recorded and logged — never an error, because a model naming a
    /// file it cannot see is a normal miss, not a broken turn.
    static func resolve(_ plan: LocalQueryPlan,
                        context: LocalPlannerContext) -> (plan: LocalQueryPlan, dropped: [String]) {
        var dropped: [String] = []

        let knownPaths = context.knownPaths
        let files = plan.files.compactMap { requested -> String? in
            if knownPaths.contains(requested) { return requested }
            let match = knownPaths.first { $0.lowercased() == requested.lowercased() }
            if let match { return match }
            dropped.append("file:\(requested)")
            return nil
        }

        let lookup = context.symbolLookup
        let symbols = plan.symbols.compactMap { requested -> String? in
            if let canonical = lookup[requested.lowercased()] { return canonical }
            dropped.append("symbol:\(requested)")
            return nil
        }

        let knownTags = Set(context.memoryTags.map { $0.lowercased() })
        let tags = plan.memoryTags.compactMap { tag -> String? in
            if knownTags.contains(tag.lowercased()) { return tag.lowercased() }
            dropped.append("tag:\(tag)")
            return nil
        }

        let skills = plan.skills.compactMap { requested -> String? in
            if let id = context.skillIDs.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) {
                return id
            }
            dropped.append("skill:\(requested)")
            return nil
        }

        let resolved = LocalQueryPlan(
            intent: plan.intent,
            terms: plan.terms,
            symbols: symbols,
            files: files,
            memoryTags: tags,
            questions: plan.questions,
            skills: dedupe(skills),
            instructions: plan.instructions
        )
        for miss in dropped {
            logger.debug("planner dropped unknown entity: \(miss, privacy: .public)")
        }
        return (resolved, dropped)
    }

    private static let logger = Logger(
        subsystem: "com.mycoder",
        category: "LocalQueryPlanner"
    )

    // MARK: - Parsing helpers

    /// Models like to wrap JSON in a fenced block or add a sentence before it.
    /// The first `{` and the matching last `}` are the object to parse.
    static func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        return String(raw[start...end])
    }

    private static func strings(_ object: [String: Any],
                                keys: [String],
                                field: String) throws -> [String] {
        guard let raw = keys.compactMap({ object[$0] }).first else { return [] }
        // A model may answer a single item without an array; accept it as one.
        let items: [Any]
        if let list = raw as? [Any] {
            items = list
        } else if raw is String {
            items = [raw]
        } else {
            throw LocalQueryPlanError.wrongType(field: field)
        }
        let itemLimit: Int
        switch field {
        case "questions": itemLimit = maxQuestions
        case "instructions": itemLimit = maxInstructions
        default: itemLimit = maxItemsPerField
        }
        guard items.count <= itemLimit else {
            throw LocalQueryPlanError.tooManyItems(field: field)
        }
        var result: [String] = []
        for item in items {
            guard let value = item as? String else {
                throw LocalQueryPlanError.wrongType(field: field)
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            try validate(value, field: field)
            if !trimmed.isEmpty { result.append(trimmed) }
        }
        return result
    }

    private static func validate(_ value: String, field: String) throws {
        let limit: Int
        switch field {
        case "questions": limit = maxQuestionLength
        case "instructions": limit = maxInstructionLength
        default: limit = maxValueLength
        }
        if value.count > limit {
            throw LocalQueryPlanError.valueTooLong(field: field)
        }
        if value.contains("\n") || value.contains("\r") {
            throw LocalQueryPlanError.codeDetected(field: field)
        }
        // Natural-language guidance may contain ordinary punctuation, but
        // not executable snippets or multiline tool blocks.
        if field == "questions" || field == "instructions" {
            if value.contains("```") || value.contains("{") || value.contains("}")
                || value.contains("<") || value.contains(">") {
                throw LocalQueryPlanError.codeDetected(field: field)
            }
            return
        }
        if value.contains(where: { codeCharacters.contains($0) }) {
            throw LocalQueryPlanError.codeDetected(field: field)
        }
        let range = NSRange(location: 0, length: (value as NSString).length)
        if lineReference?.firstMatch(in: value, options: [], range: range) != nil {
            throw LocalQueryPlanError.lineNumberDetected(field: field)
        }
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for value in values {
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count >= maxItemsPerField { break }
        }
        return result
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }
}
