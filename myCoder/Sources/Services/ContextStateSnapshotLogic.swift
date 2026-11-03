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
                      indexedFileCount: Int) -> [String: Any] {
        [
            "isPointContextEnabled": isPointContextEnabled,
            "isLocalQueryPlannerEnabled": isLocalQueryPlannerEnabled,
            "isCompiling": isCompiling,
            "stage": stageLine,
            "indexedFileCount": indexedFileCount,
            "internalModels": internalModels.map {
                ["providerID": $0.providerID, "modelID": $0.modelID]
            }
        ]
    }
}
