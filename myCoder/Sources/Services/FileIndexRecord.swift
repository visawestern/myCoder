import Foundation

/// One indexed file's metadata (plan Раздел 7 Блок 3 п.22).
struct FileIndexRecord: Codable, Equatable {
    let path: String
    var hash: String
    var size: Int
    var lastModified: TimeInterval
    var language: String
    /// Bounded UTF-8 text retained for project-file search; nil for binary/unreadable files.
    var searchableText: String?

    init(path: String,
         hash: String,
         size: Int,
         lastModified: TimeInterval,
         language: String,
         searchableText: String? = nil) {
        self.path = path
        self.hash = hash
        self.size = size
        self.lastModified = lastModified
        self.language = language
        self.searchableText = searchableText
    }
}
