import Foundation

/// Pure classification for the boundary between a failed MiMo Serve transport
/// and unrelated direct/web provider errors. The UI uses this only for the
/// `.mimoServe` route so a local, custom, or browser failure never marks Serve
/// disconnected.
enum ServeTransportFailureLogic {
    static let disconnectedMessage =
        "myCoder Serve connection was lost. Reconnect myCoder Serve and retry."

    static func isConnectionFailure(_ error: Error) -> Bool {
        if error is URLError { return true }
        let description = error.localizedDescription.lowercased()
        return description == "connection failed"
            || description.contains("network connection")
            || description.contains("timed out")
            || description.contains("not connected")
    }

    static func shouldMarkServerDisconnected(isServeRoute: Bool, error: Error) -> Bool {
        isServeRoute && isConnectionFailure(error)
    }
}
