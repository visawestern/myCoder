import Foundation

/// Pure startup readiness rules shared by the AppState connection bridge and
/// Foundation-only regression tests. A connection is never inferred from a
/// stale AppState value: only the completed health result may establish it.
enum ServerConnectionReadinessLogic {
    static func appStateConnectionState(isConnected: Bool, healthHealthy: Bool?) -> Bool {
        guard let healthHealthy else { return false }
        return healthHealthy
    }

    static func shouldLoadServerModels(isConnected: Bool, healthHealthy: Bool?) -> Bool {
        guard healthHealthy == true else { return false }
        return isConnected
    }
}
