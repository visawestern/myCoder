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
            if !rel.isEmpty,
               rel.split(separator: "/").contains(where: { MyCoderPaths.isAppDataPathComponent(String($0)) }) {
                continue
            }

            // Exclusion is a project-relative decision. The root itself is
            // always inside its own project even when an ancestor directory
            // happens to be named "build"/"dist".
            if !rel.isEmpty, ProjectFileIndexLogic.shouldExclude(
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

        var result = byPath.values.sorted { $0.path < $1.path }
        // A hard cap on growth: event batches may not push the index past the
        // same limit the baseline scan honors. Existing records stay; only
        // newly added paths beyond the cap are dropped.
        if result.count > options.maxRecords {
            let originalPaths = Set(stored.map(\.path))
            var newlyAdded = result.map(\.path).filter { !originalPaths.contains($0) }
            while result.count > options.maxRecords, let candidate = newlyAdded.popLast() {
                result.removeAll { $0.path == candidate }
            }
        }
        return result
    }

    // MARK: - Internals

    private static func relative(_ absolute: String, root: String) -> String {
        if absolute == root { return "" }
        let base = root.hasSuffix("/") ? root : root + "/"
        return absolute.hasPrefix(base) ? String(absolute.dropFirst(base.count)) : absolute
    }

    /// Removes an exact record and, when the path was a directory, its whole
    /// subtree. An empty path matches the project root's whole subtree.
    private static func removeFrom(_ byPath: inout [String: FileIndexRecord], path: String) {
        byPath.removeValue(forKey: path)
        let prefix = path.isEmpty ? "" : path + "/"
        for key in byPath.keys.filter({ $0.hasPrefix(prefix) }) {
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
            guard !prefix.contains(0) else { return nil }
            // See ProjectFileScanner: a split multi-byte character at the cap
            // must not discard the whole text.
            return String(decoding: prefix, as: UTF8.self)
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

        var visitedRel = Set<String>()
        if !rel.isEmpty { visitedRel.insert(rel) }
        // A capped batch is a partial view of the directory. Treating every
        // unvisited stored entry as deleted would wipe valid records (and was
        // observed as data loss in a directory event); only a full pass may
        // remove what it did not see.
        var truncated = false
        for case let fileURL as URL in enumerator {
            if processed >= options.maxFilesPerBatch {
                truncated = true
                break
            }
            let childRel = relative(fileURL.standardizedFileURL.path, root: root)

            if ProjectFileIndexLogic.shouldExclude(
                relativePath: childRel,
                gitignorePatterns: options.gitignorePatterns
            ) {
                // Excluded trees must not keep records from an older scan.
                removeFrom(&byPath, path: childRel)
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                continue
            }
            visitedRel.insert(childRel)
            if let record = record(for: fileURL.path, rel: childRel, options: options, fileManager: fileManager) {
                byPath[childRel] = record
            } else {
                byPath.removeValue(forKey: childRel)
            }
            processed += 1
        }

        guard !truncated else { return }
        // Full pass: stored entries inside this directory that no longer
        // exist are gone. An empty `rel` is the project root.
        let prefix = rel.isEmpty ? "" : rel + "/"
        for key in byPath.keys where key.hasPrefix(prefix) && !visitedRel.contains(key) {
            byPath.removeValue(forKey: key)
        }
    }
}
