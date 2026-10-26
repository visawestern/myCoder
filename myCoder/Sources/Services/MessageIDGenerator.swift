import Foundation

enum MessageIDGenerator {
    static func next() -> String {
        let millis = Int64(Date().timeIntervalSince1970 * 1000)
        let suffix = String(format: "%012x", millis)
        return "msg_\(suffix)"
    }
}
