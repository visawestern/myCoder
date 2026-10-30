import Foundation

enum MyCoderAutoFreeFailoverLogic {
    static func reason(errorDescription: String, failureCount: Int) -> String {
        let lower = errorDescription.lowercased()
        if lower.contains("missingsessionid") || lower.contains("missing session id") {
            return "missing session context"
        }
        if lower.contains("freetiererror")
            || lower.contains("only be used from within opencode")
            || lower.contains("only be used in opencode") {
            return "free-tier gate"
        }
        if lower.contains("429") || lower.contains("rate limit") || lower.contains("ratelimit") {
            return "rate limit"
        }
        if lower.contains("model") && (lower.contains("unavailable") || lower.contains("not found") || lower.contains("failed")) {
            return "model unavailable"
        }
        return "\(failureCount) consecutive failures"
    }
}
