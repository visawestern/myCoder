import Foundation

/// Thread-safe accumulator for the tool-call parts of ONE assistant message
/// during a web-chat driver turn. The driver emits toolCall events from a
/// background task while the UI applies parts on the main actor; this box is
/// the shared source of truth so parts are appended (not lost) and the final
/// answer never wipes them.
final class WebToolPartsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var running: [(partID: String, name: String, args: String)] = []
    private var completed: [MessagePartContent] = []

    /// A tool call started: remember it as running (result pending).
    func appendRunning(name: String, args: String, partID: String) {
        lock.lock()
        defer { lock.unlock() }
        running.append((partID, name, args))
    }

    /// A tool finished: fold the result into the oldest running call with the
    /// same tool name. If no running call matches (e.g. a result arrived for
    /// a call emitted before this turn), a completed part is appended.
    func completeLast(name: String, result: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = running.firstIndex(where: { $0.name == name }) {
            let call = running.remove(at: idx)
            completed.append(.toolCall(name: call.name, args: call.args, result: result, callID: call.partID))
        } else {
            completed.append(.toolCall(name: name, args: "", result: result, callID: UUID().uuidString))
        }
    }

    /// Snapshot of the parts: completed calls first (in order), then running
    /// calls (result == nil → the inspector shows the running state).
    var parts: [MessagePartContent] {
        lock.lock()
        defer { lock.unlock() }
        var result = completed
        for call in running {
            result.append(.toolCall(name: call.name, args: call.args, result: nil, callID: call.partID))
        }
        return result
    }
}
