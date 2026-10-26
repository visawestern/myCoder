import Foundation

/// Storage audit log (plan Раздел 8 п.46): every registry operation
/// (create/archive/restore/delete/relink/reset) is appended to
/// `~/.mycoder/logs/storage-audit.log` so future "something appeared on its
/// own" reports can be diagnosed from real history instead of guesswork.
enum StorageAuditLog {

    /// The log file location for a home directory.
    static func logURL(homeDirectory: URL) -> URL {
        MyCoderPaths.logFile(name: "storage-audit.log", homeDirectory: homeDirectory)
    }

    /// Append one timestamped audit line. Never rewrites existing entries.
    static func append(action: String, detail: String, homeDirectory: URL,
                       fileManager: FileManager = .default, now: Date = Date()) throws {
        let url = logURL(homeDirectory: homeDirectory)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now)
        let line = "\(stamp)  [\(action)] \(detail)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) { try handle.write(contentsOf: data) }
        } else {
            try line.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }
}
