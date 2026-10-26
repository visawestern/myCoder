import Foundation

/// Complete result of smart send
struct SmartSendResult: Codable, Equatable {
    /// Whether send succeeded
    let success: Bool
    /// Final response (if any)
    let response: String?
    /// Method that succeeded
    let winningMethod: String?
    /// All attempts made
    let attempts: [SendAttempt]
    /// Total duration
    let duration: TimeInterval
    /// Learned endpoint updates
    let updates: [EndpointUpdate]
}

/// Smart send that tries all methods in order with learning.
///
/// Integrates DirectWebAPIClient, SmartElementFinder, FallbackRouter,
/// and NetworkInterceptor into a single send operation.
///
/// ## Usage
/// ```swift
/// let result = await SmartSend.execute(
///     message: "Hello!",
///     config: config,
///     bridge: bridge,
///     appState: appState
/// )
/// if result.success {
///     print("Sent via \(result.winningMethod ?? "unknown")")
/// }
/// ```
///
/// ## Fallback Chain
/// 1. Direct API (fastest, no DOM)
/// 2. Smart Element (finds elements by description)
/// 3. Browser Automation (standard catalog flow)
/// 4. Manual intervention (all methods failed)
///
/// ## Learning
/// After each failure, `learnFromFailure()` updates the endpoint
/// for the next attempt. Over time, the system adapts to API changes.
enum SmartSend {

    /// Maximum number of retry attempts
    static let maxRetries = 3

    /// Delay between retries in seconds
    static let retryDelay: TimeInterval = 1.0

    /// Logger for diagnostics
    private static let logger = SmartSendLogger()

    // MARK: - Public API

    /// Execute smart send with all fallbacks.
    ///
    /// - Parameters:
    ///   - message: Message to send
    ///   - config: Provider configuration
    ///   - bridge: Browser automation bridge
    ///   - appState: Application state
    /// - Returns: Complete send result with all attempts
    ///
    /// ## Flow
    /// 1. Resolve best route via FallbackRouter
    ///   2. Execute route
    ///   3. If failed, learn and retry
    ///   4. Return result with all attempts
    public static func execute(
        message: String,
        config: WebProviderConfig,
        bridge: BrowserAutomationBridge,
        appState: AnyObject? = nil
    ) async -> SmartSendResult {
        let startTime = Date()
        var allAttempts: [SendAttempt] = []
        var allUpdates: [EndpointUpdate] = []
        var lastResult: SendResult?

        logger.log("SmartSend.execute started for vendor=\(config.vendor.rawValue), message=\(message.prefix(50))...")

        for attempt in 1...maxRetries {
            let vendor = config.vendor
            let route = await FallbackRouter.resolve(
                vendor: vendor, message: message, bridge: bridge
            )

            logger.log("Attempt \(attempt)/\(maxRetries): route=\(route)")

            guard route != .none else {
                logger.log("No route available, stopping")
                break
            }

            let result = await FallbackRouter.execute(
                route: route, message: message,
                bridge: bridge, config: config
            )

            allAttempts.append(contentsOf: result.attempts)
            lastResult = result

            logger.log("Attempt \(attempt) result: success=\(result.success), method=\(result.winningMethod ?? "none")")

            if result.success {
                let duration = Date().timeIntervalSince(startTime)
                logger.log("SmartSend succeeded via \(result.winningMethod ?? "unknown") in \(duration)s")
                return SmartSendResult(
                    success: true,
                    response: result.response,
                    winningMethod: result.winningMethod,
                    attempts: allAttempts,
                    duration: duration,
                    updates: allUpdates
                )
            }

            // Learn from failure
            if case .directAPI(let endpoint) = route,
               let lastAttempt = result.attempts.last,
               lastAttempt.error != nil {
                if let update = learnFromFailure(
                    attempt: lastAttempt,
                    endpoint: endpoint
                ) {
                    allUpdates.append(update)
                    logger.log("Learned from failure: \(update.reason)")
                }
            }

            // Wait before retry
            if attempt < maxRetries {
                logger.log("Waiting \(retryDelay)s before retry...")
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        logger.log("SmartSend failed after \(allAttempts.count) attempts in \(duration)s")
        return SmartSendResult(
            success: false,
            response: lastResult?.response,
            winningMethod: lastResult?.winningMethod,
            attempts: allAttempts,
            duration: duration,
            updates: allUpdates
        )
    }

    // MARK: - Learning

    /// Learn from a failed attempt and suggest endpoint update.
    ///
    /// - Parameters:
    ///   - attempt: Failed send attempt
    ///   - endpoint: Original endpoint
    /// - Returns: Endpoint update suggestion, or nil
    ///
    /// ## Learning Rules
    /// 1. 401 Unauthorized → token expired, need refresh
    /// 2. 403 Forbidden → CSRF token expired
    /// 3. 429 Too Many Requests → rate limited, add delay
    /// 4. 404 Not Found → endpoint changed
    /// 5. 500+ → server error, try different endpoint
    public static func learnFromFailure(
        attempt: SendAttempt,
        endpoint: ChatAPIEndpoint
    ) -> EndpointUpdate? {
        guard let error = attempt.error else { return nil }

        let errorLower = error.lowercased()

        // Token expired
        if errorLower.contains("401") || errorLower.contains("unauthorized") {
            return EndpointUpdate(
                endpoint: endpoint,
                reason: "Token expired - need refresh",
                confidence: 0.8
            )
        }

        // CSRF token expired
        if errorLower.contains("403") || errorLower.contains("forbidden") {
            return EndpointUpdate(
                endpoint: endpoint,
                reason: "CSRF token expired",
                confidence: 0.7
            )
        }

        // Rate limited
        if errorLower.contains("429") || errorLower.contains("too many requests") {
            return EndpointUpdate(
                endpoint: endpoint,
                reason: "Rate limited - add delay",
                confidence: 0.9
            )
        }

        // Endpoint not found
        if errorLower.contains("404") || errorLower.contains("not found") {
            return EndpointUpdate(
                endpoint: endpoint,
                reason: "Endpoint changed",
                confidence: 0.6
            )
        }

        // Server error
        if errorLower.contains("500") || errorLower.contains("internal server error") {
            return EndpointUpdate(
                endpoint: endpoint,
                reason: "Server error - try different endpoint",
                confidence: 0.5
            )
        }

        // Network error
        if errorLower.contains("network") || errorLower.contains("timeout") {
            return EndpointUpdate(
                endpoint: endpoint,
                reason: "Network error - check connectivity",
                confidence: 0.4
            )
        }

        return nil
    }
}

// MARK: - Logger

/// Simple logger for SmartSend diagnostics
private struct SmartSendLogger {
    private let prefix = "[SmartSend]"

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
