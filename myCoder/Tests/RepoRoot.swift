import Foundation

/// Locates the repository root robustly for source-inspection tests, instead of
/// each test hardcoding a fixed number of `.deletingLastPathComponent()` calls
/// and the source folder name (audit B6). Walks up from this file until it finds
/// `Package.swift`, so it survives folder renames and directory-depth changes.
enum RepoRoot {
    /// The repository root URL (directory containing Package.swift).
    static let url: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        // Walk up to the filesystem root at most.
        while dir.path != "/" {
            if fm.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        // Fallback: two levels up from Tests/ (myCoder/Tests -> repo root).
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    /// Read a repo-relative source file (e.g. "myCoder/Sources/Views/…").
    static func sourceText(_ relativePath: String) throws -> String {
        try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The whole chat panel source: the main file plus every focused
    /// `ChatPanelView+…` extension module (audit B3 split). Source-inspection
    /// tests assert on the panel as a unit, so moving code into an extension
    /// must not hide it from them.
    static var chatPanelSourceText: String {
        get throws {
            let views = url.appendingPathComponent("myCoder/Sources/Views")
            let names = try FileManager.default.contentsOfDirectory(atPath: views.path)
                .filter { $0.hasPrefix("ChatPanelView") && $0.hasSuffix(".swift") }
                .sorted()
            return try names.map {
                try String(contentsOf: views.appendingPathComponent($0), encoding: .utf8)
            }.joined(separator: "\n")
        }
    }

    /// The whole input-bar source: the main `InputViews.swift` plus the
    /// focused input-card modules extracted from it (audit B3 split).
    /// Source-inspection tests assert on the composer as a unit, so moving
    /// code into a sibling file must not hide it from them.
    static var inputViewsSourceText: String {
        get throws {
            let dir = url.appendingPathComponent("myCoder/Sources/Views/Components")
            let prefixes = ["InputViews", "CenteredInputCard", "BottomInputBar", "PendingMessageCard"]
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { name in
                    name.hasSuffix(".swift") && prefixes.contains { name.hasPrefix($0) }
                }
                .sorted()
            return try names.map {
                try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8)
            }.joined(separator: "\n")
        }
    }

    /// Read every source file of one module family (the main file plus the
    /// focused modules extracted from it). Source-inspection tests assert on a
    /// component as a unit, so moving code into a sibling file must not hide
    /// it from them.
    static func sourceTextOfFamily(in directory: String, prefixes: [String]) throws -> String {
        let dir = url.appendingPathComponent(directory)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { name in
                name.hasSuffix(".swift") && prefixes.contains { name.hasPrefix($0) }
            }
            .sorted()
        return try names.map {
            try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")
    }

    /// The whole message-row source (main file + row parts + cards).
    static var messageRowSourceText: String {
        get throws {
            try sourceTextOfFamily(in: "myCoder/Sources/Views/Components",
                                   prefixes: ["MessageRow", "MessageContentSegment"])
        }
    }

    /// The whole sidebar source (main file + workspace/notification/sheet parts).
    static var sidebarSourceText: String {
        get throws {
            try sourceTextOfFamily(in: "myCoder/Sources/Views",
                                   prefixes: ["Sidebar"])
        }
    }

    /// The whole per-project database source (manager + its focused modules).
    static var projectDatabaseSourceText: String {
        get throws {
            try sourceTextOfFamily(in: "myCoder/Sources/Services",
                                   prefixes: ["ProjectDatabase"])
        }
    }

    /// The whole local API server source (main file + focused route modules).
    static var apiServerSourceText: String {
        get throws {
            try sourceTextOfFamily(in: "myCoder/Sources/Services",
                                   prefixes: ["MyCoderAPIServer"])
        }
    }
}
