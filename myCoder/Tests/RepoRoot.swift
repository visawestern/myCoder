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

    /// Root folder of the production sources.
    static var sourcesURL: URL { url.appendingPathComponent("myCoder/Sources") }

    /// Every Swift source file under `relativeDirectory` (recursive), sorted by
    /// path. Source-inspection tests use this instead of walking `#filePath`
    /// themselves, so a folder rename only changes this helper.
    static func allSwiftSourceTexts(
        in relativeDirectory: String = "myCoder/Sources"
    ) throws -> [(path: String, contents: String)] {
        let root = url.appendingPathComponent(relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ) else { return [] }
        var result: [(String, String)] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            result.append((file.path, try String(contentsOf: file, encoding: .utf8)))
        }
        return result.sorted { $0.0 < $1.0 }
    }

    /// Swift sources of one flat directory, keyed by file URL.
    static func swiftSourceTexts(in relativeDirectory: String) throws -> [URL: String] {
        let dir = url.appendingPathComponent(relativeDirectory)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        var result: [URL: String] = [:]
        for name in names {
            let file = dir.appendingPathComponent(name)
            result[file] = try String(contentsOf: file, encoding: .utf8)
        }
        return result
    }

    /// Concatenated Swift sources of one flat directory.
    static func allSourceText(in relativeDirectory: String) throws -> String {
        let sources = try swiftSourceTexts(in: relativeDirectory)
        return sources.keys.sorted { $0.path < $1.path }
            .map { sources[$0] ?? "" }
            .joined(separator: "\n")
    }

    /// Root `SettingsView.swift` plus every file in the `Settings/` folder.
    static var settingsSourceText: String {
        get throws {
            let root = try sourceText("myCoder/Sources/Views/SettingsView.swift")
            let folder = try allSourceText(in: "myCoder/Sources/Views/Settings")
            return root + "\n" + folder
        }
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

    /// The whole application-state source: `AppState.swift` plus every focused
    /// `AppState+…` extension module. Source-inspection tests assert on the
    /// state object as a unit, so splitting its behaviour across sibling files
    /// must not hide it from them.
    static var appStateSourceText: String {
        get throws {
            try sourceTextOfFamily(in: "myCoder/Sources/App",
                                   prefixes: ["AppState"])
        }
    }

    /// The whole localization source (keys + every translation table).
    static var localizationSourceText: String {
        get throws {
            try sourceTextOfFamily(in: "myCoder/Sources/Services",
                                   prefixes: ["AppLocalization"])
        }
    }

    /// The whole model-settings source (the view plus its focused column
    /// modules).
    static var modelSettingsSourceText: String {
        get throws {
            try sourceTextOfFamily(in: "myCoder/Sources/Views/Settings",
                                   prefixes: ["ModelSettings"])
        }
    }
}
