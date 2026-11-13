import AppKit
import Foundation

/// Click-to-open for file paths shown in chat messages. A violet inline-code
/// token that resolves to an existing file opens a menu asking which
/// application to open it with (the default handler first, then every app
/// registered for the extension, plus Finder reveal).
enum ChatFileOpenLogic {
    static func looksLikeFilePath(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return false }
        guard !trimmed.contains("\n"), !trimmed.contains("`") else { return false }
        let lowered = trimmed.lowercased()
        for scheme in ["http://", "https://", "file://", "mailto:", "ssh://", "ftp://"] where lowered.hasPrefix(scheme) {
            return false
        }
        if trimmed.hasPrefix("./") || trimmed.hasPrefix("../") || trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return true
        }
        if trimmed.contains("/") {
            return true
        }
        let name = (trimmed as NSString).lastPathComponent
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        let ext = name[name.index(after: dot)...]
        return !ext.isEmpty && ext.count <= 12 && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }

    static func resolveFilePath(_ token: String, projectRoot: String?) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        // Хвостовая пунктуация (точка/запятая/скобка/кавычка) не является
        // частью имени файла — «App.swift.» → «App.swift».
        var candidateRaw = trimmed
        while let last = candidateRaw.last, ".,;:!?)]}>».»\"'".contains(last) {
            candidateRaw.removeLast()
        }
        guard !candidateRaw.isEmpty else { return nil }
        // Голые имена без расширения допустимы, только если ведут к
        // существующей папке (клик по папке → «Открыть в Finder»).
        let isBareName = !candidateRaw.contains("/") && !candidateRaw.hasPrefix("~")
        if !looksLikeFilePath(candidateRaw) {
            guard isBareName else { return nil }
        }
        var candidate = candidateRaw
        if candidate.hasPrefix("~") {
            candidate = (candidate as NSString).expandingTildeInPath
        }
        if !candidate.hasPrefix("/") {
            if let root = projectRoot?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty {
                candidate = (root as NSString).appendingPathComponent(candidate)
            } else {
                // Fallback для standalone-чатов: рабочая папка процесса (только
                // если файл реально существует — ложных ссылок не создаём).
                let cwd = FileManager.default.currentDirectoryPath
                guard cwd != "/" else { return nil }
                candidate = (cwd as NSString).appendingPathComponent(candidate)
            }
        }
        let standardized = URL(fileURLWithPath: candidate).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory) else { return nil }
        return standardized
    }

    static func applicationsThatCanOpen(fileURL: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
    }

    static func defaultApplication(fileURL: URL) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: fileURL)
    }

    static func orderedApplications(default defaultApp: URL?, candidates: [URL]) -> [URL] {
        var result: [URL] = []
        if let defaultApp {
            result.append(defaultApp)
        }
        for url in candidates where !result.contains(url) {
            result.append(url)
        }
        return result
    }

    static func applicationName(at appURL: URL) -> String {
        let name = appURL.deletingPathExtension().lastPathComponent
        return name.isEmpty ? appURL.lastPathComponent : name
    }

    static func open(fileURL: URL, applicationURL: URL?) {
        if let applicationURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([fileURL], withApplicationAt: applicationURL, configuration: configuration)
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }

    static func revealInFinder(fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
