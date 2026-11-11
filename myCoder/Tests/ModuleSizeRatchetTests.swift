import Foundation
import Testing

/// Ratchet for module size: every Swift source file must stay at or below the
/// 600-line module budget. Files that were already over budget when the rule
/// was introduced are listed explicitly; the list may only shrink. A listed
/// file that has become compliant must be removed from the list, otherwise the
/// test fails — that prevents the allowlist from silently staying forever.
@Suite("Module size ratchet")
struct ModuleSizeRatchetTests {
    /// Current over-budget files. Remove an entry as soon as the file is split.
    private static let overBudget: Set<String> = [
    ]

    private static let moduleBudget = 600

    /// All tracked Swift sources under `myCoder/Sources`, repo-relative.
    private static func sourceFiles() -> [String] {
        let root = RepoRoot.url.appendingPathComponent("myCoder/Sources")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        var result: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: RepoRoot.url.path + "/", with: "")
            result.append(relative)
        }
        return result.sorted()
    }

    /// Physical line count, same definition as `wc -l` (newline characters).
    private static func lineCount(of text: String) -> Int {
        text.utf8.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    @Test func noSourceFileExceedsModuleBudget() throws {
        var violations: [String] = []
        var staleAllowlist: [String] = []
        let files = Self.sourceFiles()
        #expect(!files.isEmpty)

        for file in files {
            let text = try String(
                contentsOf: RepoRoot.url.appendingPathComponent(file),
                encoding: .utf8
            )
            let lines = Self.lineCount(of: text)
            let allowed = Self.overBudget.contains(file)
            if lines > Self.moduleBudget && !allowed {
                violations.append("\(file): \(lines) строк")
            }
            if lines <= Self.moduleBudget && allowed {
                staleAllowlist.append(file)
            }
        }

        #expect(violations.isEmpty, "Файлы длиннее \(Self.moduleBudget) строк: \(violations.joined(separator: ", "))")
        #expect(staleAllowlist.isEmpty, "Эти файлы уже уложились в лимит — уберите их из списка: \(staleAllowlist.joined(separator: ", "))")
    }
}
