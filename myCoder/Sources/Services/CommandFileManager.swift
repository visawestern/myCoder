import Foundation

/// User-defined slash-command template (plan Раздел 5 Блок 1 / SET-07). A
/// command is a `.md` template in `~/.mycoder/commands/<name>.md` with an
/// optional frontmatter block (name, description) and a body that is injected
/// into the outgoing message when the command runs. Disabled state is a
/// per-name flag in UserDefaults, mirroring the plugin disable pattern.
struct CommandEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let path: String
    var isEnabled: Bool

    init(id: String, name: String, description: String = "", path: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.path = path
        self.isEnabled = isEnabled
    }
}

/// CRUD + template-resolution store for user slash commands (SET-07).
/// Foundation-only and injectable so the whole surface is unit-testable.
enum CommandFileManager {

    static let directoryName = "commands"
    private static let defaults = UserDefaults.standard
    private static let disabledKey = "disabledCommands"

    // MARK: - Paths

    static func commandsDirectory(homeDirectory: URL) -> URL {
        MyCoderPaths.commandsDir(homeDirectory: homeDirectory)
    }

    static func fileURL(name: String, homeDirectory: URL) -> URL {
        commandsDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("\(name).md")
    }

    // MARK: - Read

    /// Load commands from `~/.mycoder/commands`, parsing frontmatter for a
    /// display name and description. Files without frontmatter use the
    /// filename as the name.
    static func load(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                     fileManager: FileManager = .default) -> [CommandEntry] {
        let dir = commandsDirectory(homeDirectory: homeDirectory)
        guard let files = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [CommandEntry] = []
        for file in files where file.pathExtension.lowercased() == "md" {
            let filename = file.deletingPathExtension().lastPathComponent
            let (name, description) = frontmatter(of: file)
            results.append(CommandEntry(
                id: file.path,
                name: name ?? filename,
                description: description ?? "",
                path: file.path,
                isEnabled: !isDisabled(filename)
            ))
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Frontmatter `description:` and `name:` from a command file's leading
    /// `---` block (mirrors the skill frontmatter convention).
    static func frontmatter(of url: URL) -> (name: String?, description: String?) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, nil)
        }
        return frontmatter(in: content)
    }

    static func frontmatter(in content: String) -> (name: String?, description: String?) {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, nil) }
        var name: String?
        var description: String?
        var found = false
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { found = true; break }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"\"''"))
                switch key.lowercased() {
                case "name": name = value
                case "description": description = value
                default: break
                }
            }
        }
        return found ? (name, description) : (nil, nil)
    }

    /// Body of a command template (frontmatter stripped, trimmed).
    static func body(of url: URL) -> String {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return body(in: content)
    }

    static func body(in content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var rest: [Substring] = []
        var found = false
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                found = true
                continue
            }
            if found { rest.append(line) }
        }
        guard found else { return content.trimmingCharacters(in: .whitespacesAndNewlines) }
        return rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The full template that gets injected when a custom command runs
    /// (SET-07): the frontmatter-less body with `{{input}}` / `{{argument}}`
    /// placeholders replaced by the user's argument.
    static func templateBody(named commandName: String,
                             argument: String,
                             homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                             fileManager: FileManager = .default) -> String? {
        let url = fileURL(name: commandName, homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let body = body(of: url)
        guard !body.isEmpty else { return nil }
        let arg = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        return body
            .replacingOccurrences(of: "{{input}}", with: arg)
            .replacingOccurrences(of: "{{argument}}", with: arg)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Write

    /// Create a new command file. Throws on invalid names and duplicate names.
    static func create(name: String,
                       description: String,
                       template: String,
                       homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                       fileManager: FileManager = .default) throws {
        let clean = sanitized(name: name)
        guard !clean.isEmpty else {
            throw CommandFileError.invalidName
        }
        let url = fileURL(name: clean, homeDirectory: homeDirectory)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw CommandFileError.duplicate(clean)
        }
        try write(content: render(name: clean, description: description, template: template), to: url, fileManager: fileManager)
    }

    /// Update an existing command file (name change renames the file).
    static func update(from oldName: String,
                       name: String,
                       description: String,
                       template: String,
                       homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                       fileManager: FileManager = .default) throws {
        let oldClean = sanitized(name: oldName)
        let newClean = sanitized(name: name)
        guard !newClean.isEmpty else { throw CommandFileError.invalidName }
        let oldURL = fileURL(name: oldClean, homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: oldURL.path) else {
            throw CommandFileError.notFound(oldClean)
        }
        if oldClean != newClean {
            let newURL = fileURL(name: newClean, homeDirectory: homeDirectory)
            guard !fileManager.fileExists(atPath: newURL.path) else {
                throw CommandFileError.duplicate(newClean)
            }
            try fileManager.moveItem(at: oldURL, to: newURL)
        }
        try write(content: render(name: newClean, description: description, template: template),
                  to: fileURL(name: newClean, homeDirectory: homeDirectory),
                  fileManager: fileManager)
    }

    /// Delete a command file. Returns false when it didn't exist.
    @discardableResult
    static func delete(named name: String,
                       homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                       fileManager: FileManager = .default) throws -> Bool {
        let clean = sanitized(name: name)
        let url = fileURL(name: clean, homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        try fileManager.removeItem(at: url)
        removeDisabled(clean)
        return true
    }

    /// Render a command file from its parts.
    static func render(name: String, description: String, template: String) -> String {
        var lines = ["---", "name: \(name)"]
        if !description.isEmpty {
            lines.append("description: \(description)")
        }
        lines.append("---")
        let body = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            lines.append("")
            lines.append(body)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Enable / disable

    static func isDisabled(_ name: String) -> Bool {
        let disabled = defaults.stringArray(forKey: disabledKey) ?? []
        return disabled.contains(name)
    }

    /// Toggle a command's enabled state; returns the new state.
    static func toggleEnabled(name: String) -> Bool {
        var disabled = defaults.stringArray(forKey: disabledKey) ?? []
        if disabled.contains(name) {
            disabled.removeAll { $0 == name }
        } else {
            disabled.append(name)
        }
        defaults.set(disabled, forKey: disabledKey)
        return !isDisabled(name)
    }

    static func setEnabled(_ name: String, enabled: Bool) {
        var disabled = defaults.stringArray(forKey: disabledKey) ?? []
        if enabled {
            disabled.removeAll { $0 == name }
        } else if !disabled.contains(name) {
            disabled.append(name)
        }
        defaults.set(disabled, forKey: disabledKey)
    }

    private static func removeDisabled(_ name: String) {
        var disabled = defaults.stringArray(forKey: disabledKey) ?? []
        disabled.removeAll { $0 == name }
        defaults.set(disabled, forKey: disabledKey)
    }

    /// Keep only `[a-zA-Z0-9-_]` (dashes/slashes would break the trigger).
    static func sanitized(name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
        return cleaned
    }

    private static func write(content: String, to url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

enum CommandFileError: LocalizedError, Equatable {
    case invalidName
    case duplicate(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Command name is empty or contains unsupported characters."
        case .duplicate(let name):
            return "A command named /\(name) already exists."
        case .notFound(let name):
            return "Command /\(name) does not exist."
        }
    }
}
