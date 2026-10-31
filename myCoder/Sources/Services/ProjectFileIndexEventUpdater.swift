import Foundation

/// Applies filesystem change events to the persisted project index without
/// rescanning the whole project.
///
/// FSEvents delivers the paths that changed; this updater re-reads only those
/// (and bounded subtrees for directory events) and merges the result into the
/// stored records. A full scan is never triggered here — the baseline is
/// built once when a workspace opens (see `PointContextIndexLogic`), and every
/// later change is handled event-by-event, so a 150 GB repo costs nothing
/// until something inside it actually changes.
enum ProjectFileIndexEventUpdater {

    struct Options {
        var maxFileSize: Int = ProjectFileIndexLogic.defaultMaxFileSize
        var maxRecords: Int = ProjectFileIndexLogic.defaultMaxIndexRecords
        var searchableTextMaxBytes: Int = ProjectFileIndexLogic.defaultIndexSearchableTextMaxBytes
        var gitignorePatterns: [String] = []
        /// Hard cap on files processed per event batch. A directory event on a
        /// huge folder must not turn one edit into a scan of everything.
        var maxFilesPerBatch: Int = 2_000
    }

    static func apply(
        changedPaths: [String],
        stored: [FileIndexRecord],
        projectPath: String,
        options: Options = Options(),
        fileManager: FileManager = .default
    ) -> [FileIndexRecord] {
        let root = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        guard !root.isEmpty else { return stored }

        var byPath = ProjectFileIndexLogic.recordsByPath(stored)
        var processed = 0

        for absolute in changedPaths {
            guard processed < options.maxFilesPerBatch else { break }
            let std = URL(fileURLWithPath: absolute).standardizedFileURL.path
            guard std == root || std.hasPrefix(root + "/") else { continue }
            let rel = relative(std, root: root)
            // Never touch our own data dir (would loop on index saves).
            if rel.split(separator: "/").contains(where: { MyCoderPaths.isAppDataPathComponent(String($0)) }) {
                continue
            }

            if ProjectFileIndexLogic.shouldExclude(
                relativePath: rel,
                gitignorePatterns: options.gitignorePatterns
            ) {
                removeFrom(&byPath, path: rel)
                continue
            }

            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: std, isDirectory: &isDirectory)

            if !exists {
                // Deleted file or directory: drop the record and any subtree.
                removeFrom(&byPath, path: rel)
                continue
            }

            if isDirectory.boolValue {
                processDirectory(
                    std,
                    rel: rel,
                    root: root,
                    byPath: &byPath,
                    options: options,
                    fileManager: fileManager,
                    processed: &processed
                )
            } else {
                if let record = record(for: std, rel: rel, options: options, fileManager: fileManager) {
                    byPath[rel] = record
                } else {
                    byPath.removeValue(forKey: rel)
                }
                processed += 1
            }
        }

        return byPath.values.sorted { $0.path < $1.path }
    }

    // MARK: - Internals

    private static func relative(_ absolute: String, root: String) -> String {
        let base = root.hasSuffix("/") ? root : root + "/"
        return absolute.hasPrefix(base) ? String(absolute.dropFirst(base.count)) : absolute
    }

    /// Removes an exact record and, when the path was a directory, its whole
    /// subtree.
    private static func removeFrom(_ byPath: inout [String: FileIndexRecord], path: String) {
        byPath.removeValue(forKey: path)
        for key in byPath.keys where key.hasPrefix(path + "/") {
            byPath.removeValue(forKey: key)
        }
    }

    private static func record(
        for filePath: String,
        rel: String,
        options: Options,
        fileManager: FileManager
    ) -> FileIndexRecord? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: filePath) else { return nil }
        guard let size = (attrs[.size] as? NSNumber)?.intValue, size >= 0 else { return nil }
        guard size <= options.maxFileSize else { return nil }
        guard ProjectFileIndexLogic.shouldIndex(
            relativePath: rel,
            size: size,
            gitignorePatterns: options.gitignorePatterns,
            maxFileSize: options.maxFileSize
        ) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let searchableText: String? = {
            let prefix = data.prefix(options.searchableTextMaxBytes)
            guard !prefix.contains(0),
                  let text = String(data: prefix, encoding: .utf8) else { return nil }
            return text
        }()
        let ext = (rel as NSString).pathExtension
        return FileIndexRecord(
            path: rel,
            hash: ProjectFileScanner.hash(of: data),
            size: size,
            lastModified: mtime,
            language: ProjectFileIndexLogic.language(forExtension: ext),
            searchableText: searchableText
        )
    }

    private static func processDirectory(
        _ dir: String,
        rel: String,
        root: String,
        byPath: inout [String: FileIndexRecord],
        options: Options,
        fileManager: FileManager,
        processed: inout Int
    ) {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: dir),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else { return }

        var visitedRel = Set<String>([rel])
        for case let fileURL as URL in enumerator {
            guard processed < options.maxFilesPerBatch else { break }
            let childRel = relative(fileURL.standardizedFileURL.path, root: root)
            visitedRel.insert(childRel)

            if ProjectFileIndexLogic.shouldExclude(
                relativePath: childRel,
                gitignorePatterns: options.gitignorePatterns
            ) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                continue
            }
            if let record = record(for: fileURL.path, rel: childRel, options: options, fileManager: fileManager) {
                byPath[childRel] = record
            } else {
                byPath.removeValue(forKey: childRel)
            }
            processed += 1
        }

        // Stored entries inside this directory that no longer exist are gone.
        for key in byPath.keys where key.hasPrefix(rel + "/") && !visitedRel.contains(key) {
            byPath.removeValue(forKey: key)
        }
    }
}
