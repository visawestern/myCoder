import Foundation

enum ProjectFileIndexWatcherLogic {
    static let debounceNanoseconds: UInt64 = 300_000_000

    static func shouldInvalidate(changedPath: String, projectPath: String) -> Bool {
        let changed = URL(fileURLWithPath: changedPath).standardizedFileURL.path
        let project = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        guard !project.isEmpty, changed == project || changed.hasPrefix(project + "/") else { return false }
        let relative = changed == project ? "" : String(changed.dropFirst(project.count + 1))
        return !relative.split(separator: "/").contains(where: { MyCoderPaths.isAppDataPathComponent(String($0)) })
    }

    static func shouldApply(
        eventProjectPath: String,
        activeProjectPath: String,
        eventGeneration: UInt64,
        activeGeneration: UInt64
    ) -> Bool {
        eventGeneration == activeGeneration
            && URL(fileURLWithPath: eventProjectPath).standardizedFileURL.path
                == URL(fileURLWithPath: activeProjectPath).standardizedFileURL.path
    }
}
