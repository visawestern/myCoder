import Foundation

enum ProjectFileIndexWatcherLifecycleLogic {
    static func shouldRestart(oldProjectPath: String?, newProjectPath: String?) -> Bool {
        canonical(oldProjectPath) != canonical(newProjectPath)
    }

    private static func canonical(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
