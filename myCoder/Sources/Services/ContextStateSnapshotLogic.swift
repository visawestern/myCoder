import Foundation

/// Builds the `context` block of the `/api/state` snapshot.
///
/// The context pipeline was invisible over HTTP: the snapshot reported the
/// selection and the UI, but not whether point context was on, whether the
/// local planner was on, which model is assigned to internal work, or what
/// stage the assembly is in right now. A turn that hangs for ten minutes looks
/// identical to a turn that never started without this.
enum ContextStateSnapshotLogic {

    static func block(isPointContextEnabled: Bool,
                      isLocalQueryPlannerEnabled: Bool,
                      isCompiling: Bool,
                      stageLine: String,
                      internalModels: [InternalModelRef],
                      indexedFileCount: Int,
                      log: ContextAssemblyLogLogic.Log = .empty) -> [String: Any] {
        var snapshot: [String: Any] = [
            "isPointContextEnabled": isPointContextEnabled,
            "isLocalQueryPlannerEnabled": isLocalQueryPlannerEnabled,
            "isCompiling": isCompiling,
            "stage": stageLine,
            "indexedFileCount": indexedFileCount,
            "internalModels": internalModels.map {
                ["providerID": $0.providerID, "modelID": $0.modelID]
            },
            "assemblyRunning": log.isRunning,
            "assemblySummary": log.summary,
            "assemblyLog": log.entries.map { entry -> [String: Any] in
                [
                    "key": entry.key,
                    "title": entry.title,
                    "status": entry.status.rawValue,
                    "request": entry.request,
                    "processing": entry.processing,
                    "result": entry.result,
                    "durationMs": entry.durationMilliseconds.map { $0 as Any } ?? NSNull()
                ]
            }
        ]
        return snapshot
    }
}
