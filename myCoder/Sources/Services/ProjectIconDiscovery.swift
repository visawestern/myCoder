import Foundation

/// Finds a project's own icon (favicon/logo) in its root folder.
///
/// Rules (user directive 2026-11-12):
/// - the project root is scanned first, then a small whitelist of standard
///   project subfolders (`assets`, `public`, `static`, `Resources`, `img`,
///   `images`) — each only at depth 1, never recursed further;
/// - `node_modules`, vendored dependencies, submodules and any other folder
///   are never searched — the icon must belong to the project itself;
/// - well-known file names are matched case-insensitively;
/// - when several exist, `candidateNames` order decides (favicon first), and
///   a root icon always wins over a subfolder icon.
enum ProjectIconDiscovery {

    static let candidateNames: [String] = [
        "favicon.ico",
        "favicon.png",
        "apple-touch-icon.png",
        "favicon.webp",
        "favicon.jpg",
        "favicon.svg",
        "logo.png",
        "logo.svg",
        "logo.webp",
        "logo.jpg",
        "icon.png",
        "icon.svg",
        "icon.webp",
        "symbol.png",
        "symbol.svg",
        "mark.png",
        "mark.svg",
        "brand.png",
        "brand.svg",
        "app-logo.png",
        "app-icon.png",
        "AppIcon.icns",
    ]

    /// Standard project subfolders searched at depth 1 (never deeper).
    static let allowedSubdirectories: [String] = [
        "assets",
        "public",
        "static",
        "Resources",
        "img",
        "images",
    ]

    /// The URL of the project's icon file, or nil when none is found.
    static func iconURL(
        forProjectAt projectPath: String,
        fileManager: FileManager = .default,
        names: [String] = candidateNames,
        subdirectories: [String] = allowedSubdirectories
    ) -> URL? {
        guard !projectPath.isEmpty else { return nil }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: projectPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let root = URL(fileURLWithPath: projectPath)
        var baseURLs = [root]
        for sub in subdirectories {
            let url = root.appendingPathComponent(sub)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                baseURLs.append(url)
            }
        }

        for base in baseURLs {
            if let url = firstMatch(in: base, fileManager: fileManager, names: names) {
                return url
            }
        }
        return nil
    }

    private static func firstMatch(
        in base: URL,
        fileManager: FileManager,
        names: [String]
    ) -> URL? {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: base.path) else {
            return nil
        }
        // Lowercased name → actual on-disk name (the filesystem may be
        // case-insensitive, and we must return the real file name).
        var entriesByLowercasedName: [String: String] = [:]
        for entry in entries {
            entriesByLowercasedName[entry.lowercased()] = entry
        }

        for name in names {
            guard let actualName = entriesByLowercasedName[name.lowercased()] else { continue }
            let url = base.appendingPathComponent(actualName)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                return url
            }
        }
        return nil
    }
}
