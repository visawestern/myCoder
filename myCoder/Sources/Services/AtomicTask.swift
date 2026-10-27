import Foundation

/// A pointer to real code the local model selected.
struct TaskReference: Equatable {
    let path: String
    let symbol: String?
    let startLine: Int?
    let endLine: Int?
    let why: String?
}

/// The atomic task assembled by the LOCAL model: what to do, how to verify it,
/// and which existing code it touches. The local model never writes code
/// (user directive D7) — it only names real functions and variables.
struct AtomicTask: Equatable {
    let atomicTask: String
    let tddSteps: [String]
    let acceptance: [String]
    let refs: [TaskReference]
    let knownGaps: [String]

    var isEmpty: Bool { atomicTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Parses the answer of the local model into an `AtomicTask`.
///
/// Two shapes are accepted (user directive D10): a JSON object, or free text
/// with `path:line` references. A broken answer is an error — never a silent
/// empty task (user directive D4).
enum AtomicTaskParser {

    static func parse(_ text: String) throws -> AtomicTask {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LocalCompilerError.invalidJSON(detail: "empty answer", raw: text)
        }
        if let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
           let dictionary = object as? [String: Any] {
            return try parseJSON(dictionary, raw: trimmed)
        }
        // Free form: the task text plus `path:line` references.
        let refs = freeFormReferences(in: trimmed)
        guard !refs.isEmpty else {
            throw LocalCompilerError.invalidJSON(detail: "not a JSON object and no path:line references", raw: trimmed)
        }
        return AtomicTask(
            atomicTask: trimmed,
            tddSteps: [],
            acceptance: [],
            refs: refs,
            knownGaps: []
        )
    }

    // MARK: - JSON

    private static func parseJSON(_ dictionary: [String: Any], raw: String) throws -> AtomicTask {
        let taskText = (dictionary["atomicTask"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !taskText.isEmpty else {
            throw LocalCompilerError.missingField("atomicTask")
        }
        var tddSteps: [String] = []
        if let tdd = dictionary["tdd"] as? [String: Any] {
            tddSteps = stringArray(tdd["steps"])
        }
        if tddSteps.isEmpty {
            tddSteps = stringArray(dictionary["tddSteps"])
        }
        let acceptance = stringArray(dictionary["acceptance"])
        let knownGaps = stringArray(dictionary["knownGaps"])
        var refs: [TaskReference] = []
        for rawRef in (dictionary["refs"] as? [[String: Any]]) ?? [] {
            guard let path = (rawRef["path"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { continue }
            refs.append(TaskReference(
                path: path,
                symbol: optionalString(rawRef["symbol"]),
                startLine: optionalInt(rawRef["startLine"]),
                endLine: optionalInt(rawRef["endLine"]),
                why: optionalString(rawRef["why"])
            ))
        }
        return AtomicTask(
            atomicTask: taskText,
            tddSteps: tddSteps,
            acceptance: acceptance,
            refs: refs,
            knownGaps: knownGaps
        )
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let items = value as? [Any] else { return [] }
        return items.compactMap { item -> String? in
            guard let text = item as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func optionalString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    // MARK: - Free form

    private static func freeFormReferences(in text: String) -> [TaskReference] {
        let pattern = #"([A-Za-z0-9_./\-]+\.[A-Za-z0-9]{1,8}):(\d+)(?:\s*[-–—]\s*(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        var refs: [TaskReference] = []
        var seen = Set<String>()
        for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges >= 2 else { continue }
            let path = ns.substring(with: match.range(at: 1))
            let start = Int(ns.substring(with: match.range(at: 2))) ?? 0
            var end: Int? = nil
            if match.numberOfRanges >= 3, match.range(at: 3).location != NSNotFound {
                end = Int(ns.substring(with: match.range(at: 3)))
            }
            let key = "\(path):\(start)"
            guard seen.insert(key).inserted else { continue }
            refs.append(TaskReference(path: path, symbol: nil, startLine: start, endLine: end, why: nil))
        }
        return refs
    }
}
