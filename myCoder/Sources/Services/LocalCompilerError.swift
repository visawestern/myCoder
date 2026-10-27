import Foundation

/// Every failure of the local context compiler. The compiler never hides a
/// failure behind a stub: the error travels to the user (user directive D4).
enum LocalCompilerError: Error, Equatable, LocalizedError {
    /// No local model is configured (or none is OpenAI-compatible).
    case noLocalModels
    /// The local model could not be reached.
    case transportFailed(model: String, reason: String)
    /// The local model answered with nothing.
    case emptyResponse(model: String)
    /// The answer is not valid JSON.
    case invalidJSON(detail: String, raw: String)
    /// A required field of the atomic task is missing or empty.
    case missingField(String)
    /// The local model pointed at a file that does not exist in the project.
    case unknownReference(path: String)
    /// A referenced file could not be read.
    case materializationFailed(path: String, reason: String)
    /// The prompt does not fit the remote model window and cannot be split.
    case promptDoesNotFit(model: String, bytes: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .noLocalModels:
            return "No local model is configured for the context compiler (add one in Providers → Local)."
        case .transportFailed(let model, let reason):
            return "Local model '\(model)' is unreachable: \(reason)"
        case .emptyResponse(let model):
            return "Local model '\(model)' returned an empty answer"
        case .invalidJSON(let detail, _):
            return "Local model returned invalid JSON: \(detail)"
        case .missingField(let field):
            return "Local model answer is missing the required field '\(field)'"
        case .unknownReference(let path):
            return "Local model pointed at a file that is not in the project: \(path)"
        case .materializationFailed(let path, let reason):
            return "Cannot read '\(path)': \(reason)"
        case .promptDoesNotFit(let model, let bytes, let limit):
            return "Context does not fit the window of '\(model)' (\(bytes) > \(limit) bytes)"
        }
    }
}
