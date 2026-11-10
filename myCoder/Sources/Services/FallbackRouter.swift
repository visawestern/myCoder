import Foundation

/// Route type for smart fallback sending messages
enum SmartSendRoute: Equatable {
    /// Direct API call with endpoint
    case directAPI(ChatAPIEndpoint)
    /// Smart element detection with selector
    case smartElement(String, ElementType)
    /// Standard browser automation from catalog
    case browserAutomation
    /// No route available
    case none
}

/// Result of a send attempt
struct SendAttempt: Codable, Equatable {
    /// Method used
    let method: String
    /// Whether attempt succeeded
    let success: Bool
    /// Duration in seconds
    let duration: TimeInterval
    /// Error message (if any)
    let error: String?
    /// Response (if any)
    let response: String?
    /// Confidence score
    let confidence: Float
}

/// Complete send result with all attempts
struct SendResult: Codable, Equatable {
    /// Whether overall send succeeded
    let success: Bool
    /// Final response (if any)
    let response: String?
    /// All attempts made
    let attempts: [SendAttempt]
    /// Method that ultimately succeeded
    let winningMethod: String?
    /// Total duration
    let duration: TimeInterval
}

/// Endpoint update from failure analysis
struct EndpointUpdate: Codable, Equatable {
    /// Updated endpoint
    let endpoint: ChatAPIEndpoint
    /// Reason for update
    let reason: String
    /// Confidence in update
    let confidence: Float
}

/// Fallback router that selects the best method for sending messages.
///
/// Routes between: Direct API → Smart Element → Browser Automation.
/// Each method is tried in order; first success wins.
///
/// ## Usage
/// ```swift
/// let route = await FallbackRouter.resolve(
///     vendor: .kimi,
///     message: "Hello!",
///     bridge: bridge
/// )
/// let result = await FallbackRouter.execute(
///     route: route,
///     message: "Hello!",
///     bridge: bridge,
///     config: config
/// )
/// ```
///
/// ## Fallback Chain
/// 1. Direct API (if endpoint discovered via NetworkInterceptor)
/// 2. Smart Element (if element found via SmartElementFinder)
/// 3. Browser Automation (standard catalog selectors)
/// 4. None (all methods failed)
///
/// ## Circuit Breaker
/// After 3 consecutive failures for a method, that method is skipped
/// for 60 seconds.
enum FallbackRouter {

    /// Circuit breaker: consecutive failures before skipping
    static let circuitBreakerThreshold = 3

    /// Circuit breaker: cooldown period in seconds
    static let circuitBreakerCooldown: TimeInterval = 60

    /// UserDefaults key for circuit breaker state
    private static let circuitBreakerKey = "SmartSendCircuitBreaker"

    /// Whether to persist state (disabled during tests)
    nonisolated(unsafe) private static var persistState = true

    /// Track consecutive failures per method
    nonisolated(unsafe) private static var failureCounts: [String: Int] = [:]
    nonisolated(unsafe) private static var lastFailureTimes: [String: Date] = [:]

    /// Logger for diagnostics
    static let logger = FallbackRouterLogger()

    // MARK: - Persistence

    /// Load circuit breaker state from UserDefaults (merge, don't replace)
    private static func loadState() {
        guard persistState else { return }
        guard let data = UserDefaults.standard.data(forKey: circuitBreakerKey),
              let state = try? JSONDecoder().decode([String: CircuitBreakerState].self, from: data) else {
            return
        }
        for (method, state) in state {
            // Only update if not already set in memory
            if failureCounts[method] == nil {
                failureCounts[method] = state.failureCount
                lastFailureTimes[method] = state.lastFailureTime
            }
        }
    }

    /// Save circuit breaker state to UserDefaults
    private static func saveState() {
        guard persistState else { return }
        var state: [String: CircuitBreakerState] = [:]
        for (method, count) in failureCounts {
            state[method] = CircuitBreakerState(
                failureCount: count,
                lastFailureTime: lastFailureTimes[method]
            )
        }
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: circuitBreakerKey)
        }
    }

    /// Circuit breaker state for persistence
    private struct CircuitBreakerState: Codable {
        let failureCount: Int
        let lastFailureTime: Date?
    }

    // MARK: - Public API

    /// Resolve the best route for sending a message.
    ///
    /// - Parameters:
    ///   - vendor: Chat vendor (kimi, qwen, chatgpt)
    ///   - message: Message to send
    ///   - bridge: Browser automation bridge
    /// - Returns: Best available route
    ///
    /// ## Resolution Order
    /// 1. Check circuit breaker for each method
    /// 2. Try Direct API (if endpoint available)
    /// 3. Try Smart Element (if element found)
    /// 4. Fall back to Browser Automation
    public static func resolve(
        vendor: WebChatVendor,
        message: String,
        bridge: BrowserAutomationBridge
    ) async -> SmartSendRoute {
        logger.log("Resolving route for vendor=\(vendor.rawValue)")

        // Try Direct API first
        if !isCircuitOpen(method: "directAPI") {
            // For known vendors, use hardcoded endpoints
            if let knownEndpoint = await getKnownEndpoint(for: vendor, bridge: bridge) {
                logger.log("Using known endpoint for \(vendor.rawValue): \(knownEndpoint.url)")
                return .directAPI(knownEndpoint)
            }
            
            // Fallback: try to discover from network
            await NetworkInterceptor.install(bridge: bridge)
            let requests = await NetworkInterceptor.captureRequests(bridge: bridge)
            logger.log("Captured \(requests.count) network requests")
            if let endpoint = NetworkInterceptor.findChatAPI(requests: requests) {
                logger.log("Found direct API endpoint: \(endpoint.url)")
                return .directAPI(endpoint)
            }
        } else {
            logger.log("DirectAPI circuit is open, skipping")
        }

        // Try Smart Element
        if !isCircuitOpen(method: "smartElement") {
            let result = await SmartElementFinder.findElement(
                bridge: bridge,
                description: "send button",
                context: vendor.rawValue
            )
            if let result = result, result.confidence >= SmartElementFinder.confidenceThreshold {
                logger.log("Found smart element: \(result.selector) (confidence: \(result.confidence))")
                return .smartElement(result.selector, result.elementType)
            }
        } else {
            logger.log("SmartElement circuit is open, skipping")
        }

        // Fall back to Browser Automation
        if !isCircuitOpen(method: "browserAutomation") {
            logger.log("Using browser automation")
            return .browserAutomation
        }

        logger.log("All routes exhausted, returning .none")
        return .none
    }

    /// Get known API endpoint for a vendor.
    private static func getKnownEndpoint(
        for vendor: WebChatVendor,
        bridge: BrowserAutomationBridge
    ) async -> ChatAPIEndpoint? {
        switch vendor {
        case .kimi:
            // Audit 2026-09-09 (live): the hardcoded kimi.com connect endpoint
            // 401s on every call for kimi.ai accounts (wrong host + stale
            // device/session/traffic ids) and burned all 3 SmartSend attempts
            // before browser automation ever ran. No known working endpoint —
            // go straight to the browser.
            return nil
        case .qwen:
            return nil
        case .chatgpt:
            return nil
        case .claude:
            return nil
        case .custom:
            return nil
        }
    }

    /// Try to find a direct API endpoint.
    ///
    /// - Parameters:
    ///   - vendor: Chat vendor
    ///   - bridge: Browser automation bridge
    /// - Returns: Chat API endpoint if found
    public static func tryDirectAPI(
        vendor: WebChatVendor,
        bridge: BrowserAutomationBridge
    ) async -> ChatAPIEndpoint? {
        await NetworkInterceptor.install(bridge: bridge)
        let requests = await NetworkInterceptor.captureRequests(bridge: bridge)
        return NetworkInterceptor.findChatAPI(requests: requests)
    }

    /// Try to find an element via smart detection.
    ///
    /// - Parameters:
    ///   - vendor: Chat vendor
    ///   - bridge: Browser automation bridge
    ///   - element: Element type to find
    /// - Returns: CSS selector if found
    public static func trySmartElement(
        vendor: WebChatVendor,
        bridge: BrowserAutomationBridge,
        element: ElementType
    ) async -> String? {
        let description: String
        switch element {
        case .sendButton: description = "send button"
        case .input: description = "text input field"
        case .modelDropdown: description = "model selection dropdown"
        case .newChat: description = "new chat button"
        case .effortToggle: description = "effort or thinking level toggle"
        case .stopButton: description = "stop generation button"
        default: description = "\(element.description)"
        }

        let result = await SmartElementFinder.findElement(
            bridge: bridge,
            description: description,
            context: vendor.rawValue
        )
        return result?.selector
    }

    /// Execute a send route.
    ///
    /// - Parameters:
    ///   - route: Send route to execute
    ///   - message: Message to send
    ///   - bridge: Browser automation bridge
    ///   - config: Provider configuration
    /// - Returns: Send result with all attempts
    ///
    /// ## Execution
    /// 1. DirectAPI → URLSession with cookies
    /// 2. SmartElement → bridge.typeText + bridge.click
    /// 3. BrowserAutomation → standard catalog flow
    public static func execute(
        route: SmartSendRoute,
        message: String,
        bridge: BrowserAutomationBridge,
        config: WebProviderConfig
    ) async -> SendResult {
        let startTime = Date()

        switch route {
        case .directAPI(let endpoint):
            let attempt = await executeDirectAPI(
                message: message, endpoint: endpoint, bridge: bridge
            )
            let duration = Date().timeIntervalSince(startTime)
            recordAttempt(method: "directAPI", success: attempt.success)
            return SendResult(
                success: attempt.success,
                response: attempt.response,
                attempts: [attempt],
                winningMethod: attempt.success ? "directAPI" : nil,
                duration: duration
            )

        case .smartElement(let selector, _):
            let attempt = await executeSmartElement(
                message: message, selector: selector,
                elementType: .sendButton, bridge: bridge
            )
            let duration = Date().timeIntervalSince(startTime)
            recordAttempt(method: "smartElement", success: attempt.success)
            return SendResult(
                success: attempt.success,
                response: attempt.response,
                attempts: [attempt],
                winningMethod: attempt.success ? "smartElement" : nil,
                duration: duration
            )

        case .browserAutomation:
            let attempt = await executeBrowserAutomation(
                message: message, bridge: bridge, config: config
            )
            let duration = Date().timeIntervalSince(startTime)
            recordAttempt(method: "browserAutomation", success: attempt.success)
            return SendResult(
                success: attempt.success,
                response: attempt.response,
                attempts: [attempt],
                winningMethod: attempt.success ? "browserAutomation" : nil,
                duration: duration
            )

        case .none:
            let duration = Date().timeIntervalSince(startTime)
            return SendResult(
                success: false, response: nil,
                attempts: [], winningMethod: nil,
                duration: duration
            )
        }
    }

    // MARK: - Execution Helpers

    /// Execute direct API send
    private static func executeDirectAPI(
        message: String,
        endpoint: ChatAPIEndpoint,
        bridge: BrowserAutomationBridge
    ) async -> SendAttempt {
        let startTime = Date()
        let cookies: [BrowserCookie]
        do {
            cookies = try await bridge.cookies()
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return SendAttempt(
                method: "directAPI",
                success: false,
                duration: duration,
                error: "Failed to get cookies: \(error.localizedDescription)",
                response: nil,
                confidence: 0.0
            )
        }

        let result = await DirectWebAPIClient.send(
            message: message,
            endpoint: endpoint,
            cookies: cookies
        )

        return SendAttempt(
            method: "directAPI",
            success: result.success,
            duration: result.duration,
            error: result.error,
            response: result.response,
            confidence: 0.9
        )
    }

    /// Execute smart element send
    private static func executeSmartElement(
        message: String,
        selector: String,
        elementType: ElementType,
        bridge: BrowserAutomationBridge
    ) async -> SendAttempt {
        let startTime = Date()

        do {
            // Type message into input
            let inputSelector = await findInputElement(bridge: bridge)
            try await bridge.typeText(message, into: inputSelector, humanized: false, pressEnter: true)

            // Small delay for UI to process
            try? await Task.sleep(nanoseconds: 200_000_000)

            // Click the target element
            try await bridge.click(selector: selector)

            let duration = Date().timeIntervalSince(startTime)
            return SendAttempt(
                method: "smartElement",
                success: true,
                duration: duration,
                error: nil,
                response: nil,
                confidence: 0.7
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return SendAttempt(
                method: "smartElement",
                success: false,
                duration: duration,
                error: error.localizedDescription,
                response: nil,
                confidence: 0.0
            )
        }
    }


    // MARK: - Circuit Breaker

    /// Check if circuit is open (method should be skipped)
    private static func isCircuitOpen(method: String) -> Bool {
        loadState()
        guard let count = failureCounts[method],
              let lastFailure = lastFailureTimes[method] else {
            return false
        }
        if count >= circuitBreakerThreshold {
            let elapsed = Date().timeIntervalSince(lastFailure)
            if elapsed < circuitBreakerCooldown {
                return true
            } else {
                // Cooldown expired, reset
                failureCounts[method] = 0
                saveState()
                return false
            }
        }
        return false
    }

    /// Record attempt result for circuit breaker
    private static func recordAttempt(method: String, success: Bool) {
        loadState()
        if success {
            failureCounts[method] = 0
        } else {
            failureCounts[method] = (failureCounts[method] ?? 0) + 1
            lastFailureTimes[method] = Date()
        }
        saveState()
    }

    // MARK: - Testing Helpers

    /// Reset circuit breaker state for a method (testing only)
    static func resetCircuitBreaker(method: String) {
        UserDefaults.standard.removeObject(forKey: circuitBreakerKey)
        failureCounts[method] = nil
        lastFailureTimes[method] = nil
    }

    /// Disable persistence for tests
    static func disablePersistenceForTesting() {
        persistState = false
    }

    /// Re-enable persistence after tests
    static func enablePersistenceForTesting() {
        persistState = true
    }

    /// Check if circuit is open (testing only) - reads from in-memory state only
    static func isCircuitOpenForTesting(method: String) -> Bool {
        guard let count = failureCounts[method],
              let lastFailure = lastFailureTimes[method] else {
            return false
        }
        if count >= circuitBreakerThreshold {
            let elapsed = Date().timeIntervalSince(lastFailure)
            if elapsed < circuitBreakerCooldown {
                return true
            } else {
                failureCounts[method] = 0
                return false
            }
        }
        return false
    }

    /// Record attempt for testing - writes to in-memory state only
    static func recordAttemptForTesting(method: String, success: Bool) {
        if success {
            failureCounts[method] = 0
        } else {
            failureCounts[method] = (failureCounts[method] ?? 0) + 1
            lastFailureTimes[method] = Date()
        }
    }

    /// Set last failure time for testing - writes to in-memory state only
    static func setLastFailureTimeForTesting(method: String, time: Date) {
        lastFailureTimes[method] = time
    }
}

/// Simple logger for FallbackRouter diagnostics
struct FallbackRouterLogger {
    private let prefix = "[FallbackRouter]"

    func log(_ message: String) {
        let formatted = "\(prefix) \(message)"
        #if DEBUG
        print(formatted)
        #endif
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(formatted)\n"
        if let data = line.data(using: .utf8) {
            let url = MyCoderPaths.logFile(name: "smartsend.log", homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
