import Foundation
import CoreFoundation

/// Validation/result formatting for the internal API. Validation completes
/// before the caller is allowed to acquire a bridge or start the engine.
enum BrowserFetchAPILogic {
    static func arguments(from params: [String: Any]) throws -> [String: String] {
        var scalars: [String: String] = [:]
        for (key, value) in params {
            if let text = value as? String {
                scalars[key] = text
            } else if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    scalars[key] = number.boolValue ? "true" : "false"
                } else if let integer = Int(number.stringValue) {
                    scalars[key] = String(integer)
                } else {
                    throw AppActionError.invalidParameter(key, "Expected a string, boolean or integer")
                }
            } else {
                throw AppActionError.invalidParameter(key, "Expected a string, boolean or integer")
            }
        }
        let normalized = WebToolProtocolEmulator.normalizedArguments(for: .browserFetch, from: scalars)
        guard let url = normalized["url"], !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppActionError.missingParameter("url")
        }
        switch BrowserFetchPlanner.parse(normalized) {
        case .success:
            return normalized
        case .failure(let error):
            throw AppActionError.invalidParameter("browser_fetch", error.message)
        }
    }

    @MainActor
    static func perform(params: [String: Any],
                        execute: ([String: String]) async -> String) async throws -> [String: Any] {
        let normalized = try arguments(from: params)
        let output = await execute(normalized)
        return result(output: output)
    }

    static func result(output: String) -> [String: Any] {
        let failed = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("error:")
        let marker = "ATTACHED_IMAGE:image/png:"
        var image: Data?
        if let range = output.range(of: marker, options: .backwards) {
            let encoded = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: encoded), data.count > 8,
               Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] {
                image = data
            }
        }
        var result: [String: Any] = ["ok": !failed, "output": output, "screenshot": image != nil]
        if let image { result["screenshotBytes"] = image.count }
        return result
    }
}
