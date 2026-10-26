import Foundation

/// Pure per-project storage administration (plan Раздел 8 п.25/п.28):
/// real per-project DB sizes and bulk archive operations, testable without
/// touching the global database.
enum ProjectStorageAdmin {

    /// Size in bytes of the project's `.mycoder/project.db` (0 when missing).
    static func projectDatabaseSize(projectPath: String) -> Int64 {
        let url = ProjectDatabaseLocator.databaseURL(projectPath: projectPath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    /// Archive every non-archived project not opened in the last N days
    /// (plan Раздел 8 п.25 — user-driven bulk archive, never automatic).
    static func archiveAllInactive(days: Int, now: Date = Date(), in projects: [ProjectRegistryEntry]) -> [ProjectRegistryEntry] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return projects.map { entry in
            guard !entry.isArchived, entry.lastOpenedAt < cutoff else { return entry }
            var updated = entry
            updated.archivedAt = now
            return updated
        }
    }

    // MARK: - Quota (plan Раздел 8 п.50)

    /// A read-only snapshot of total per-project storage vs. a threshold.
    /// Informative, not blocking: the UI offers archiving as a remedy.
    struct StorageQuotaStatus: Equatable {
        let totalBytes: Int64
        let thresholdBytes: Int64
        /// Bytes used by ACTIVE projects that are archivable (not opened in
        /// `inactiveDays`) — the actionable "free up by archiving" number.
        let archivableBytes: Int64
        /// Bytes used by already-archived projects (not reclaimable by archiving
        /// again, but relevant context for the storage panel).
        let archivedBytes: Int64

        var isOverQuota: Bool { totalBytes > thresholdBytes }
        var overByBytes: Int64 { max(0, totalBytes - thresholdBytes) }
        var overPercent: Int { thresholdBytes > 0 ? Int((Double(totalBytes) / Double(thresholdBytes) * 100).rounded()) : 0 }
    }

    /// Aggregate every per-project DB size (real on-disk bytes) and compare
    /// against the threshold. `inactiveDays` defines which active projects
    /// count as "archivable" for the suggested cleanup.
    static func quotaStatus(projects: [ProjectRegistryEntry],
                            thresholdBytes: Int64,
                            inactiveDays: Int = 30,
                            now: Date = Date()) -> StorageQuotaStatus {
        let cutoff = now.addingTimeInterval(-Double(inactiveDays) * 86400)
        var total: Int64 = 0
        var archivable: Int64 = 0
        var archived: Int64 = 0
        for entry in projects {
            let size = projectDatabaseSize(projectPath: entry.path)
            total += size
            if entry.isArchived {
                archived += size
            } else if entry.lastOpenedAt < cutoff {
                archivable += size
            }
        }
        return StorageQuotaStatus(totalBytes: total,
                                  thresholdBytes: thresholdBytes,
                                  archivableBytes: archivable,
                                  archivedBytes: archived)
    }
}
