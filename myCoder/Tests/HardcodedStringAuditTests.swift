import Testing
import Foundation
@testable import myCoder

/// Closes the historical `docs/qa/hardcoded_strings_checklist.md` (2026-08-09).
/// User-facing labels, alerts, help texts and AppKit panel prompts must go
/// through `L.t`. The scanner covers the common SwiftUI constructors; dynamic
/// interpolations are skipped because their parts are data, not static copy.
/// The allowlist contains only technical tokens that are not natural language.
@MainActor
@Suite("No hardcoded user-facing strings in views")
struct HardcodedStringAuditTests {

    private static let allowed: Set<String> = [
        "/compact", "MI", "/name",
        "localhost:11434 or 192.168.1.10:4096",
        "R", "T", "⌘⇧P",
    ]

    private static let patterns: [String] = [
        #"\b(?:Button|Text|Label|TextField|SecureField|Toggle|Picker|Section|MenuItem)\("([^"\\]*(?:\\.[^"\\]*)*)""#,
        #"\.(?:help|alert|accessibilityLabel|accessibilityHint|navigationTitle|confirmationDialog)\("([^"\\]*(?:\\.[^"\\]*)*)""#,
        #"panel\.(?:prompt|message|title) = "([^"\\]*(?:\\.[^"\\]*)*)""#,
    ]

    @Test("Views use L.t for labels, alerts, help and panel prompts")
    func noHardcodedUserFacingStrings() throws {
        let regexes = try Self.patterns.map {
            try NSRegularExpression(pattern: $0)
        }
        let sources = try RepoRoot.allSwiftSourceTexts(in: "myCoder/Sources/Views")
        var violations: [String] = []

        for (path, contents) in sources {
            for (index, line) in contents.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                for regex in regexes {
                    let range = NSRange(location: 0, length: (line as NSString).length)
                    for match in regex.matches(in: line, range: range) {
                        guard match.numberOfRanges > 1,
                              let literalRange = Range(match.range(at: 1), in: line) else { continue }
                        let literal = String(line[literalRange])
                        if literal.contains("\\(") { continue }
                        if literal.rangeOfCharacter(from: .letters) == nil { continue }
                        if Self.allowed.contains(literal) { continue }
                        violations.append("\(path):\(index + 1): \(literal)")
                    }
                }
            }
        }

        #expect(violations.isEmpty,
                "Hardcoded user-facing strings:\n\(violations.joined(separator: "\n"))")
    }
}
