import Foundation

/// Decides when the project file list backing the `@`-mention dropdown needs a
/// re-scan (audit P12 — the `@` list was always empty because indexing was
/// never wired). Pure/testable; AppState holds the cached list and calls the
/// real ProjectFileScanner when this says so.
struct ProjectFilesCacheState: Equatable {
    var projectPath: String
    var fileNames: [String]
    var scannedAt: Date
}

enum ProjectFilesCacheLogic {
    /// Time-to-live for a cached scan; re-scan when older (files may change).
    static let ttlSeconds: TimeInterval = 30

    /// Should we (re)scan? True when there's no cache, the project changed, or
    /// the cache is stale.
    static func needsRescan(cache: ProjectFilesCacheState?, currentPath: String, now: Date = Date()) -> Bool {
        guard !currentPath.isEmpty else { return false }   // no project → nothing to scan
        guard let cache = cache else { return true }
        if cache.projectPath != currentPath { return true }
        return now.timeIntervalSince(cache.scannedAt) > ttlSeconds
    }

    /// File names to offer for `@` mentions from a cached state for the given
    /// project (empty if the cache is for a different project).
    static func fileNames(cache: ProjectFilesCacheState?, currentPath: String) -> [String] {
        guard let cache = cache, cache.projectPath == currentPath else { return [] }
        return cache.fileNames
    }
}
