import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Real recursive file scanner producing FileIndexRecords for a project
/// (plan Раздел 7 Блок 3). Pure Foundation + CryptoKit — fully testable on a
/// temp directory (no FSEvents needed for the scan itself). The FSEvents
/// subscription that triggers re-scans is a thin app-layer wrapper around this.
enum ProjectFileScanner {
    /// Scan `root` recursively and return index records for indexable files.
    /// Honors ProjectFileIndexLogic excludes/size caps and optional gitignore
    /// patterns. Skips unreadable files rather than throwing.
    static func scan(root: String,
                    gitignorePatterns: [String] = [],
                    maxFileSize: Int = ProjectFileIndexLogic.defaultMaxFileSize,
                    fileManager: FileManager = .default) -> [FileIndexRecord] {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else { return [] }

        var records: [FileIndexRecord] = []
        for case let fileURL as URL in enumerator {
            let rel = relativePath(of: fileURL, from: rootURL)
            // Prune excluded directories early so we don't descend into them.
            if ProjectFileIndexLogic.shouldExclude(relativePath: rel, gitignorePatterns: gitignorePatterns) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            let size = values?.fileSize ?? 0
            guard ProjectFileIndexLogic.shouldIndex(relativePath: rel, size: size,
                                                    gitignorePatterns: gitignorePatterns,
                                                    maxFileSize: maxFileSize) else { continue }
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let ext = (rel as NSString).pathExtension
            let searchableText: String? = {
                let prefix = Data(data.prefix(ProjectFileIndexLogic.defaultSearchableTextMaxBytes))
                guard !prefix.contains(0),
                      let text = String(data: prefix, encoding: .utf8) else { return nil }
                return text
            }()
            records.append(FileIndexRecord(
                path: rel,
                hash: hash(of: data),
                size: size,
                lastModified: mtime,
                language: ProjectFileIndexLogic.language(forExtension: ext),
                searchableText: searchableText
            ))
        }
        return records.sorted { $0.path < $1.path }
    }

    /// Content hash for incremental change detection. SHA-256 on Apple
    /// platforms; a deterministic FNV-1a fallback where CryptoKit is absent
    /// (Linux CI) — both are stable per content, which is all the delta needs.
    static func hash(of data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        var h: UInt64 = 0xcbf29ce484222325
        for byte in data {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return String(format: "%016x", h)
        #endif
    }

    static func relativePath(of url: URL, from root: URL) -> String {
        let full = url.standardizedFileURL.path
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return full.hasPrefix(base) ? String(full.dropFirst(base.count)) : url.lastPathComponent
    }

    /// Full incremental index update: scan, diff against current records,
    /// return the delta to apply to the project index DB.
    static func incrementalUpdate(root: String,
                                 current: [FileIndexRecord],
                                 gitignorePatterns: [String] = []) -> ProjectFileIndexLogic.IndexDelta {
        let scanned = scan(root: root, gitignorePatterns: gitignorePatterns)
        return ProjectFileIndexLogic.computeDelta(current: current, scanned: scanned)
    }
}
