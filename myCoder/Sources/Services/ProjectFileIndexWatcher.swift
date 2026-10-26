import Foundation

#if canImport(CoreServices)
import CoreServices
#endif

#if canImport(CoreServices)
final class ProjectFileIndexWatcher {
    private let projectPath: String
    private let generation: UInt64
    private let onInvalidate: (String, UInt64) -> Void
    private let callbackQueue = DispatchQueue(label: "com.mycoder.file-index-watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pendingWork: DispatchWorkItem?
    private var isStopped = false

    init(projectPath: String,
         generation: UInt64,
         onInvalidate: @escaping (String, UInt64) -> Void) {
        self.projectPath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        self.generation = generation
        self.onInvalidate = onInvalidate
    }

    func start() {
        guard stream == nil, !projectPath.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [projectPath] as CFArray
        let eventFlags: FSEventStreamCreateFlags = UInt32(
            truncatingIfNeeded: kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        stream = FSEventStreamCreate(
            nil,
            { _, info, count, pathPointers, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<ProjectFileIndexWatcher>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                let typedPaths = pathPointers.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                let paths = (0..<count).map { index in
                    String(cString: typedPaths[index])
                }
                watcher.handle(paths: paths)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            eventFlags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        if !FSEventStreamStart(stream) {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    func stop() {
        callbackQueue.sync {
            isStopped = true
            pendingWork?.cancel()
            pendingWork = nil
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }
    }

    private func handle(paths: [String]) {
        guard !isStopped,
              paths.contains(where: {
                  ProjectFileIndexWatcherLogic.shouldInvalidate(
                      changedPath: $0,
                      projectPath: projectPath
                  )
              }) else { return }
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else { return }
            self.onInvalidate(self.projectPath, self.generation)
        }
        pendingWork = work
        callbackQueue.asyncAfter(
            deadline: .now() + .nanoseconds(Int(ProjectFileIndexWatcherLogic.debounceNanoseconds)),
            execute: work
        )
    }

    deinit {
        stop()
    }
}
#else
/// FSEvents is unavailable outside macOS. The type remains constructible so
/// AppState has one lifecycle path and Linux can verify the pure contracts.
final class ProjectFileIndexWatcher {
    init(projectPath: String,
         generation: UInt64,
         onInvalidate: @escaping (String, UInt64) -> Void) {}

    func start() {}
    func stop() {}
}
#endif
