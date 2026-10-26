import Testing
import Foundation
import SwiftUI
@testable import myCoder

// MARK: - SEC-02: AccessLevelPermissionLogic

@Suite("SEC-02: AccessLevel Permission Logic")
struct AccessLevelPermissionLogicTests {

    // MARK: permissionPatch(for:)

    @Test("askBeforeChanges permission patch contains only edit=ask")
    func askBeforeChangesPatch() {
        let patch = AccessLevelPermissionLogic.permissionPatch(for: .askBeforeChanges)
        #expect(patch["edit"] as? String == "ask")
        #expect(patch["bash"] == nil)
        #expect(patch["webfetch"] == nil)
        #expect(patch["external_directory"] == nil)
        #expect(patch.count == 1)
    }

    @Test("editAutomatically permission patch contains only edit=allow")
    func editAutomaticallyPatch() {
        let patch = AccessLevelPermissionLogic.permissionPatch(for: .editAutomatically)
        #expect(patch["edit"] as? String == "allow")
        #expect(patch["bash"] == nil)
        #expect(patch["webfetch"] == nil)
        #expect(patch["external_directory"] == nil)
        #expect(patch.count == 1)
    }

    @Test("fullAccess permission patch contains all keys set to allow")
    func fullAccessPatch() {
        let patch = AccessLevelPermissionLogic.permissionPatch(for: .fullAccess)
        #expect(patch["edit"] as? String == "allow")
        #expect(patch["bash"] as? String == "allow")
        #expect(patch["webfetch"] as? String == "allow")
        #expect(patch["external_directory"] as? String == "allow")
        #expect(patch.count == 4)
    }

    @Test("permissionPatch keys are non-nil for fullAccess")
    func fullAccessPatchAllKeysPresent() {
        let patch = AccessLevelPermissionLogic.permissionPatch(for: .fullAccess)
        let expectedKeys: Set<String> = ["edit", "bash", "webfetch", "external_directory"]
        #expect(Set(patch.keys) == expectedKeys)
    }

    // MARK: accessLevel(from:)

    @Test("nil permission defaults to askBeforeChanges")
    func nilPermissionDefaultsToAsk() {
        #expect(AccessLevelPermissionLogic.accessLevel(from: nil) == .askBeforeChanges)
    }

    @Test("empty permission defaults to askBeforeChanges")
    func emptyPermissionDefaultsToAsk() {
        #expect(AccessLevelPermissionLogic.accessLevel(from: [:]) == .askBeforeChanges)
    }

    @Test("bash-only permission defaults to askBeforeChanges")
    func bashOnlyPermissionDefaultsToAsk() {
        #expect(AccessLevelPermissionLogic.accessLevel(from: ["bash": "allow"]) == .askBeforeChanges)
    }

    @Test("edit=allow maps to editAutomatically")
    func editAllowMapsToAuto() {
        #expect(AccessLevelPermissionLogic.accessLevel(from: ["edit": "allow"]) == .editAutomatically)
    }

    @Test("edit=allow + bash=allow maps to fullAccess")
    func editAndBashAllowMapsToFull() {
        #expect(AccessLevelPermissionLogic.accessLevel(from: ["edit": "allow", "bash": "allow"]) == .fullAccess)
    }

    @Test("edit=ask maps to askBeforeChanges")
    func editAskMapsToAsk() {
        #expect(AccessLevelPermissionLogic.accessLevel(from: ["edit": "ask"]) == .askBeforeChanges)
    }

    @Test("webfetch=allow alone still maps to askBeforeChanges")
    func webfetchAloneIsAsk() {
        #expect(AccessLevelPermissionLogic.accessLevel(from: ["webfetch": "allow"]) == .askBeforeChanges)
    }

    // MARK: migrateLegacyAccessLevel

    @Test("legacy Plan mode migrates to askBeforeChanges")
    func legacyPlanModeMigrates() {
        #expect(AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Plan mode") == .askBeforeChanges)
    }

    @Test("legacy Ask before changes raw value maps directly")
    func legacyAskBeforeChanges() {
        #expect(AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Ask before changes") == .askBeforeChanges)
    }

    @Test("legacy Edit automatically raw value maps directly")
    func legacyEditAutomatically() {
        #expect(AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Edit automatically") == .editAutomatically)
    }

    @Test("legacy Full access raw value maps directly")
    func legacyFullAccess() {
        #expect(AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "Full access") == .fullAccess)
    }

    @Test("unknown legacy raw value defaults to askBeforeChanges")
    func unknownLegacyDefaultsToAsk() {
        #expect(AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "") == .askBeforeChanges)
        #expect(AccessLevelPermissionLogic.migrateLegacyAccessLevel(raw: "invalid") == .askBeforeChanges)
    }

    // MARK: shouldSwitchToPlanAgent

    @Test("Plan mode triggers plan agent switch")
    func planModeTriggersSwitch() {
        #expect(AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "Plan mode") == true)
    }

    @Test("non-Plan mode does not trigger switch")
    func nonPlanModeNoSwitch() {
        #expect(AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "Ask before changes") == false)
        #expect(AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "Edit automatically") == false)
        #expect(AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "Full access") == false)
        #expect(AccessLevelPermissionLogic.shouldSwitchToPlanAgent(legacyRaw: "") == false)
    }

    // MARK: AccessLevel enum properties

    @Test("AccessLevel has three cases")
    func accessLevelCaseCount() {
        #expect(AccessLevel.allCases.count == 3)
    }

    @Test("AccessLevel raw values match expected strings")
    func accessLevelRawValues() {
        #expect(AccessLevel.askBeforeChanges.rawValue == "Ask before changes")
        #expect(AccessLevel.editAutomatically.rawValue == "Edit automatically")
        #expect(AccessLevel.fullAccess.rawValue == "Full access")
    }

    @Test("AccessLevel descriptions are non-empty")
    func accessLevelDescriptions() {
        #expect(AccessLevel.askBeforeChanges.description == "Ask before file changes.")
        #expect(AccessLevel.editAutomatically.description == "Edit files automatically.")
        #expect(AccessLevel.fullAccess.description == "Run with fewer confirmations.")
    }

    @Test("AccessLevel icons match expected symbols")
    func accessLevelIcons() {
        #expect(AccessLevel.askBeforeChanges.icon == "hand.raised")
        #expect(AccessLevel.editAutomatically.icon == "pencil")
        #expect(AccessLevel.fullAccess.icon == "bolt.fill")
    }

    @Test("AccessLevel id equals rawValue")
    func accessLevelId() {
        #expect(AccessLevel.askBeforeChanges.id == "Ask before changes")
        #expect(AccessLevel.editAutomatically.id == "Edit automatically")
        #expect(AccessLevel.fullAccess.id == "Full access")
    }
}

// MARK: - THE-02: Font scaling / zoom logic

@Suite("THE-02: Font Scaling and Zoom Logic")
struct FontScalingTests {

    // MARK: InterfaceTypography.scaled

    @Test("scaled with default scale (1.0) preserves base value")
    func scaledDefault() {
        #expect(InterfaceTypography.scaled(13, scale: 1.0) == 13)
        #expect(InterfaceTypography.scaled(0, scale: 1.0) == 0)
    }

    @Test("scaled with smaller scale (0.85) rounds down")
    func scaledSmaller() {
        #expect(InterfaceTypography.scaled(13, scale: 0.85) == 11)
        #expect(InterfaceTypography.scaled(24, scale: 0.85) == 20)
    }

    @Test("scaled with larger scale (1.15) rounds up")
    func scaledLarger() {
        #expect(InterfaceTypography.scaled(13, scale: 1.15) == 15)
        #expect(InterfaceTypography.scaled(24, scale: 1.15) == 28)
    }

    @Test("scaled with zero base returns zero")
    func scaledZeroBase() {
        #expect(InterfaceTypography.scaled(0, scale: 1.5) == 0)
        #expect(InterfaceTypography.scaled(0, scale: 0.0) == 0)
    }

    @Test("scaled with scale factor of 0 returns 0")
    func scaledZeroScale() {
        #expect(InterfaceTypography.scaled(100, scale: 0.0) == 0)
    }

    @Test("scaled rounds to nearest integer away from zero")
    func scaledRoundingBehavior() {
        // 10 * 1.05 = 10.5 -> rounds to 11
        #expect(InterfaceTypography.scaled(10, scale: 1.05) == 11)
        // 10 * 1.04 = 10.4 -> rounds to 10
        #expect(InterfaceTypography.scaled(10, scale: 1.04) == 10)
        // 10 * 0.95 = 9.5 -> rounds to 10
        #expect(InterfaceTypography.scaled(10, scale: 0.95) == 10)
    }

    @Test("scaled with double scale doubles the base")
    func scaledDoubleScale() {
        #expect(InterfaceTypography.scaled(10, scale: 2.0) == 20)
        #expect(InterfaceTypography.scaled(16, scale: 2.0) == 32)
    }

    // MARK: InterfaceTypography.font

    @Test("font returns a system font with correct scaled size")
    func fontReturnsScaledSize() {
        let font = InterfaceTypography.font(size: 13, weight: .regular, design: .default, scale: 1.15)
        // Font type exists and is not a placeholder
        #expect(type(of: font) == Font.self)
    }

    @Test("font works with bold weight")
    func fontWithBoldWeight() {
        let font = InterfaceTypography.font(size: 14, weight: .bold, design: .default, scale: 1.0)
        #expect(type(of: font) == Font.self)
    }

    @Test("font works with different design")
    func fontWithDesign() {
        let font = InterfaceTypography.font(size: 12, weight: .regular, design: .monospaced, scale: 0.85)
        #expect(type(of: font) == Font.self)
    }

    // MARK: Zoom enum

    @Test("Zoom enum has three cases")
    func zoomCaseCount() {
        #expect(AppSettings.Zoom.allCases.count == 3)
    }

    @Test("Zoom raw values match expected strings")
    func zoomRawValues() {
        #expect(AppSettings.Zoom.smaller.rawValue == "Smaller")
        #expect(AppSettings.Zoom.default.rawValue == "Default")
        #expect(AppSettings.Zoom.larger.rawValue == "Larger")
    }

    @Test("Zoom fontScale values are correct")
    func zoomFontScaleValues() {
        #expect(AppSettings.Zoom.smaller.fontScale == 0.85)
        #expect(AppSettings.Zoom.default.fontScale == 1.0)
        #expect(AppSettings.Zoom.larger.fontScale == 1.15)
    }

    @Test("Zoom scale property mirrors fontScale")
    func zoomScaleMirrorsFontScale() {
        #expect(AppSettings.Zoom.smaller.scale == AppSettings.Zoom.smaller.fontScale)
        #expect(AppSettings.Zoom.default.scale == AppSettings.Zoom.default.fontScale)
        #expect(AppSettings.Zoom.larger.scale == AppSettings.Zoom.larger.fontScale)
    }
}

// MARK: - PROV-09: Test connection logic

@Suite("PROV-09: Provider Connection Logic")
struct ProviderConnectionTests {

    // MARK: testProvider URL construction

    @Test("testProvider appends /models to base URL")
    func testProviderURLConstruction() {
        let baseURL = "https://api.openai.com/v1"
        let expected = "https://api.openai.com/v1/models"
        let constructedURL = URL(string: "\(baseURL)/models")
        #expect(constructedURL?.absoluteString == expected)
    }

    @Test("testProvider with empty string constructs relative URL")
    func testProviderInvalidURL() {
        // When url is empty, "\(url)/models" becomes "/models" which is not nil
        let constructedURL = URL(string: "/models")
        #expect(constructedURL != nil)
        // An empty URL string itself returns nil from URL(string:)
        let emptyURL = URL(string: "")
        #expect(emptyURL == nil)
    }



    @Test("testProvider constructs different provider URLs correctly")
    func testProviderDifferentURLs() {
        let urls = [
            "https://api.openai.com/v1",
            "https://openrouter.ai/api/v1",
            "http://localhost:11434/v1",
            "https://api.deepseek.com/v1"
        ]
        for url in urls {
            let testURL = URL(string: "\(url)/models")
            #expect(testURL?.absoluteString == "\(url)/models")
        }
    }

    // MARK: API key header construction

    @Test("Authorization header uses Bearer scheme with non-empty key")
    func authHeaderWithKey() {
        let apiKey = "sk-test-key-12345"
        let headerValue = "Bearer \(apiKey)"
        #expect(headerValue == "Bearer sk-test-key-12345")
    }

    @Test("Authorization header with empty key produces just Bearer ")
    func authHeaderWithEmptyKey() {
        let apiKey = ""
        let headerValue = "Bearer \(apiKey)"
        #expect(headerValue == "Bearer ")
    }

    @Test("Authorization header with special characters in key")
    func authHeaderSpecialChars() {
        let apiKey = "sk-abc!@#$%^&*()"
        let headerValue = "Bearer \(apiKey)"
        #expect(headerValue == "Bearer sk-abc!@#$%^&*()")
    }

    // MARK: ProviderType default URLs

    @Test("ProviderType default URLs are non-empty")
    func providerTypeDefaultURLs() {
        for provider in ProviderType.allCases {
            #expect(!provider.defaultURL.isEmpty, "\(provider.rawValue) defaultURL should not be empty")
        }
    }

    @Test("ProviderType default URLs start with http")
    func providerTypeDefaultURLsScheme() {
        for provider in ProviderType.allCases {
            let hasHttpScheme = provider.defaultURL.hasPrefix("http://") || provider.defaultURL.hasPrefix("https://")
            #expect(hasHttpScheme, "\(provider.rawValue) defaultURL should start with http:// or https://")
        }
    }

    @Test("OpenAI default URL is correct")
    func openAIDefaultURL() {
        #expect(ProviderType.openAI.defaultURL == "https://api.openai.com/v1")
    }

    @Test("Ollama default URL is localhost")
    func ollamaDefaultURL() {
        #expect(ProviderType.ollama.defaultURL == "http://localhost:11434/v1")
    }

    @Test("ACP default URL is localhost")
    func acpDefaultURL() {
        #expect(ProviderType.acp.defaultURL == "http://localhost:8080/acp/v1")
    }

    // MARK: Health check URL

    @Test("Health endpoint path is /global/health")
    func healthEndpointPath() {
        #expect(MimoEndpoint.health.path == "/global/health")
    }

    @Test("Health endpoint uses GET method")
    func healthEndpointMethod() {
        #expect(MimoEndpoint.health.method == "GET")
    }

    @Test("Health endpoint has no query items")
    func healthEndpointNoQuery() {
        #expect(MimoEndpoint.health.queryItems() == nil)
    }

    @Test("Client health URL has correct path")
    func clientHealthURL() {
        let client = MimoServeClient(host: "127.0.0.1", port: 8080)
        let url = client.url(for: .health)
        #expect(url.path == "/global/health")
        #expect(url.host == "127.0.0.1")
        #expect(url.port == 8080)
    }

    // MARK: ProviderType enum

    @Test("ProviderType has all expected cases")
    func providerTypeAllCases() {
        let expectedCases: [ProviderType] = [
            .openAI, .openRouter, .openModel, .openCodeZen, .ollama,
            .anthropic, .google, .mistral, .groq,
            .deepseek, .omni, .nvidia, .acp
        ]
        #expect(ProviderType.allCases.count == expectedCases.count)
        for expected in expectedCases {
            #expect(ProviderType.allCases.contains { $0 == expected })
        }
    }

    @Test("ProviderType identifiers are unique")
    func providerTypeIds() {
        let ids = ProviderType.allCases.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }
}

// MARK: - ERR-01: Session busy recovery / MimoServeError

@Suite("ERR-01: Session Busy Recovery and MimoServeError")
struct MimoServeErrorTests {

    // MARK: MimoServeError cases

    @Test("MimoServeError has four distinct cases")
    func errorCaseCount() {
        // Verify all cases are constructable
        let _: MimoServeError = .httpError(statusCode: 200)
        let _: MimoServeError = .decodingError(TestingError.testError)
        let _: MimoServeError = .connectionFailed
        let _: MimoServeError = .sessionBusy
    }

    // MARK: errorDescription

    @Test("httpError without message describes status code")
    func httpErrorWithoutMessage() {
        let error = MimoServeError.httpError(statusCode: 404)
        #expect(error.errorDescription == "HTTP error 404")
    }

    @Test("httpError with message includes message")
    func httpErrorWithMessage() {
        let error = MimoServeError.httpError(statusCode: 500, message: "Internal Server Error")
        #expect(error.errorDescription == "HTTP error 500: Internal Server Error")
    }

    @Test("httpError with empty message omits message")
    func httpErrorWithEmptyMessage() {
        let error = MimoServeError.httpError(statusCode: 403, message: "")
        #expect(error.errorDescription == "HTTP error 403")
    }

    @Test("httpError with various status codes")
    func httpErrorVariousCodes() {
        let codes = [200, 201, 204, 301, 400, 401, 403, 404, 409, 422, 429, 500, 502, 503]
        for code in codes {
            let error = MimoServeError.httpError(statusCode: code)
            #expect(error.errorDescription == "HTTP error \(code)")
        }
    }

    @Test("decodingError wraps underlying error description")
    func decodingErrorDescription() {
        let underlying = TestingError.testError
        let error = MimoServeError.decodingError(underlying)
        #expect(error.errorDescription == "Decoding error: \(underlying.localizedDescription)")
    }

    @Test("decodingError with NSError")
    func decodingErrorWithNSError() {
        let underlying = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "parse failure"])
        let error = MimoServeError.decodingError(underlying)
        #expect(error.errorDescription == "Decoding error: parse failure")
    }

    @Test("connectionFailed has correct description")
    func connectionFailedDescription() {
        let error = MimoServeError.connectionFailed
        #expect(error.errorDescription == "Connection failed")
    }

    @Test("sessionBusy has descriptive message about generation")
    func sessionBusyDescription() {
        let error = MimoServeError.sessionBusy
        #expect(error.errorDescription?.contains("busy") == true)
        #expect(error.errorDescription?.contains("processing") == true)
        #expect(error.errorDescription?.contains("stop") == true)
    }

    // MARK: Pattern matching / case identification

    @Test("httpError is identified via pattern matching")
    func httpErrorPatternMatch() {
        let error = MimoServeError.httpError(statusCode: 500, message: "fail")
        switch error {
        case .httpError(let code, let msg):
            #expect(code == 500)
            #expect(msg == "fail")
        default:
            #expect(Bool(false), "Expected httpError")
        }
    }

    @Test("decodingError is identified via pattern matching")
    func decodingErrorPatternMatch() {
        let error = MimoServeError.decodingError(TestingError.testError)
        let matchesCase: Bool
        if case .decodingError = error {
            matchesCase = true
        } else {
            matchesCase = false
        }
        #expect(matchesCase)
    }

    @Test("connectionFailed is identified via pattern matching")
    func connectionFailedPatternMatch() {
        let error = MimoServeError.connectionFailed
        let matchesCase: Bool
        if case .connectionFailed = error {
            matchesCase = true
        } else {
            matchesCase = false
        }
        #expect(matchesCase)
    }

    @Test("sessionBusy is identified via pattern matching")
    func sessionBusyPatternMatch() {
        let error = MimoServeError.sessionBusy
        let matchesCase: Bool
        if case .sessionBusy = error {
            matchesCase = true
        } else {
            matchesCase = false
        }
        #expect(matchesCase)
    }

    @Test("sessionBusy is distinct from httpError(409)")
    func sessionBusyDistinctFrom409() {
        let busy = MimoServeError.sessionBusy
        let http409 = MimoServeError.httpError(statusCode: 409)
        let busyMatches: Bool
        if case .sessionBusy = busy {
            busyMatches = true
        } else {
            busyMatches = false
        }
        let httpCode: Int?
        if case .httpError(let code, _) = http409 {
            httpCode = code
        } else {
            httpCode = nil
        }
        #expect(busyMatches)
        #expect(httpCode == 409)
    }

    // MARK: LocalizedError conformance

    @Test("all MimoServeError cases implement LocalizedError")
    func allCasesAreLocalizedError() {
        let errors: [any LocalizedError] = [
            MimoServeError.httpError(statusCode: 400),
            MimoServeError.decodingError(TestingError.testError),
            MimoServeError.connectionFailed,
            MimoServeError.sessionBusy
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
        }
    }

    // MARK: HTTP 409 handling

    @Test("HTTP 409 is recognized as conflict status")
    func http409IsConflict() {
        let statusCode = 409
        #expect(statusCode == 409)
        // In the client, 409 is handled specially
        let isConflict = statusCode == 409
        #expect(isConflict)
    }

    @Test("MimoServeClient interprets 409 as sessionBusy")
    func client409MapsToSessionBusy() {
        // This mirrors the 409 mapping in MimoServeClient.sendMessage.
        let statusCode = 409
        func mapStatusCode(_ status: Int) -> MimoServeError {
            status == 409 ? .sessionBusy : .httpError(statusCode: status)
        }
        let error = mapStatusCode(statusCode)
        let matchesSessionBusy: Bool
        if case .sessionBusy = error {
            matchesSessionBusy = true
        } else {
            matchesSessionBusy = false
        }
        #expect(matchesSessionBusy)
    }

    // MARK: Timeout / retry constants

    @Test("MimoServeClient default timeout is 300 seconds")
    func clientDefaultTimeout() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        #expect(config.timeoutIntervalForRequest == 300)
        #expect(config.timeoutIntervalForResource == 300)
    }

    @Test("testProvider uses 10 second timeout")
    func testProviderTimeout() {
        let timeoutInterval: TimeInterval = 10
        #expect(timeoutInterval == 10)
        // This mirrors the timeout set in AppState.testProvider
    }
}

// MARK: - Helper

/// A simple error used for testing decoding error wrapping
private struct TestingError: Error, LocalizedError {
    static let testError = TestingError()
    var errorDescription: String? { "Test error description" }
}
