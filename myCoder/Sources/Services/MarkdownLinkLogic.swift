import Foundation

/// Назначение markdown-ссылки: веб-URL, локальный путь или неподдерживаемая
/// схема. Локальные пути (относительные к корню проекта, абсолютные, `~/`,
/// `file://`) рендерятся как ссылки с открытием через меню файла; веб-URL
/// открываются в браузере; остальное показывается как текст.
enum MarkdownLinkKind: Equatable {
    case web(URL)
    case file(String)
    case unsupported
}

enum MarkdownLinkLogic {

    /// Классифицирует содержимое `(…)` markdown-ссылки.
    static func kind(for destination: String) -> MarkdownLinkKind {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unsupported }
        let lowered = trimmed.lowercased()

        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            if let url = URL(string: trimmed), url.host != nil {
                return .web(url)
            }
            return .unsupported
        }

        var candidate = trimmed
        if lowered.hasPrefix("file://") {
            candidate = String(candidate.dropFirst(7))
            guard !candidate.isEmpty else { return .unsupported }
        }

        // Любая другая схема (`ftp://`, `mailto:`, `ssh://`, `tel:` и т.п.)
        // не является ни веб-URL, ни локальным путём. Имена файлов с
        // двоеточием на macOS невозможны, поэтому отсечение безопасно.
        let schemePattern = #"^[A-Za-z][A-Za-z0-9+.-]*:"#
        if candidate.range(of: schemePattern, options: .regularExpression) != nil {
            return .unsupported
        }

        if candidate.hasPrefix("/") || candidate.hasPrefix("./") || candidate.hasPrefix("../")
            || candidate.hasPrefix("~") || candidate.contains("/") {
            return .file(candidate)
        }
        if ChatFileOpenLogic.looksLikeFilePath(candidate) {
            return .file(candidate)
        }
        return .unsupported
    }

    /// Резолвит локальное назначение в абсолютный путь существующего
    /// файла/папки (nil, если файла нет или путь вне проекта).
    static func resolveFile(_ destination: String, projectRoot: String?) -> String? {
        guard case .file = kind(for: destination) else { return nil }
        return ChatFileOpenLogic.resolveFilePath(destination, projectRoot: projectRoot)
    }
}
