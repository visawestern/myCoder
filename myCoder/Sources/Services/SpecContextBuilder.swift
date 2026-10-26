import Foundation

/// Builds a bounded, secret-free snapshot of an existing project folder so the
/// spec planner can stay consistent with the codebase that is already there.
/// This is deliberately read-only and deterministic: the same tree always
/// produces the same context string.
enum SpecContextBuilder {
    static let defaultMaxCharacters = 12_000

    private static let ignoredDirectories: Set<String> = [
        ".git", ".build", ".svn", ".hg", "node_modules", "Pods", "Carthage",
        "DerivedData", ".next", "dist", "build", "vendor", "venv", ".venv",
        "__pycache__", ".pytest_cache", "target", "out", "coverage", ".idea",
        ".vscode", "bin", "obj"
    ]

    private static let ignoredFileNames: Set<String> = [
        ".env", ".netrc", ".npmrc", ".pypirc", ".git-credentials",
        "id_rsa", "id_ed25519", "credentials.json", "secrets.json", "secrets.yml"
    ]

    private static let ignoredExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "mobileprovision", "keystore", "jks"
    ]

    private static let keyFileNames: [String] = [
        "README.md", "README", "readme.md", "Package.swift", "package.json",
        "Cargo.toml", "go.mod", "pyproject.toml", "requirements.txt", "Gemfile",
        "composer.json", "Makefile", "Dockerfile", "docker-compose.yml",
        "docker-compose.yaml", "tsconfig.json", "vite.config.ts", "next.config.js",
        "Info.plist", "config.json"
    ]

    static func build(projectPath: String, maxCharacters: Int = defaultMaxCharacters) -> String {
        let root = URL(fileURLWithPath: projectPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return "" }

        let entries = collectEntries(root: root)
        guard !entries.isEmpty else { return "" }

        var result = """
        ## Repository context

        Project: \(root.lastPathComponent)
        Existing files (\(entries.count)):
        """
        for path in entries.prefix(400) {
            result += "\n- \(path)"
        }
        if entries.count > 400 {
            result += "\n- … \(entries.count - 400) more files"
        }

        let keyFiles = keyFiles(from: entries, root: root)
        if !keyFiles.isEmpty {
            result += "\n\n### Key files"
            for file in keyFiles {
                result += "\n\n#### \(file.relativePath)\n```\n\(file.content)\n```"
            }
        }

        if result.count > maxCharacters {
            result = String(result.prefix(maxCharacters)) + "\n\n… repository context truncated"
        }
        return result
    }

    private struct KeyFile {
        let relativePath: String
        let content: String
    }

    private static func collectEntries(root: URL) -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let rootPath = root.resolvingSymlinksInPath().path
        var files: [String] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if ignoredDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, !isIgnoredFile(url) else { continue }
            let filePath = url.resolvingSymlinksInPath().path
            guard filePath.hasPrefix(rootPath + "/") else { continue }
            let relative = String(filePath.dropFirst(rootPath.count + 1))
            if relative.split(separator: "/").contains(where: { ignoredDirectories.contains(String($0)) }) {
                continue
            }
            files.append(relative)
        }
        return files.sorted()
    }

    private static func isIgnoredFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return ignoredFileNames.contains(name)
            || ignoredExtensions.contains(url.pathExtension.lowercased())
    }

    private static func keyFiles(from entries: [String], root: URL) -> [KeyFile] {
        let ranked = entries.compactMap { relative -> (Int, String)? in
            let name = (relative as NSString).lastPathComponent
            if keyFileNames.contains(name) {
                return (keyFileNames.firstIndex(of: name) ?? 0, relative)
            }
            if name.hasPrefix("README") {
                return (keyFileNames.count + 1, relative)
            }
            return nil
        }
        .sorted { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }

        var result: [KeyFile] = []
        for (_, relative) in ranked.prefix(12) {
            let url = root.appendingPathComponent(relative)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize, size <= 80_000,
                  let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            result.append(KeyFile(
                relativePath: relative,
                content: String(clean.prefix(3_500))
            ))
        }
        return result
    }
}
