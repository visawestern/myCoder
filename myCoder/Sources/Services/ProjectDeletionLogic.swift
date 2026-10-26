import Foundation

enum ProjectDeletionLogic {
    static let defaultChunkSize = 128

    static func chunks<T>(for items: [T], chunkSize: Int = defaultChunkSize) -> [[T]] {
        guard chunkSize > 0 else { return items.isEmpty ? [] : [items] }
        var result: [[T]] = []
        var start = 0
        while start < items.count {
            let end = min(start + chunkSize, items.count)
            result.append(Array(items[start..<end]))
            start = end
        }
        return result
    }

    static func progress(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 1 }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    static func canDeleteProjectData(at projectPath: String) -> Bool {
        let trimmed = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path != "/"
    }
}
