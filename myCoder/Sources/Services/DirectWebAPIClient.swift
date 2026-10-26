import Foundation

/// Result of a direct API call
struct DirectAPIResult: Codable, Equatable {
    /// Whether the request succeeded
    let success: Bool
    /// Response body (if any)
    let response: String?
    /// Error message (if any)
    let error: String?
    /// HTTP status code
    let statusCode: Int
    /// Response headers
    let headers: [String: String]
    /// Request duration in seconds
    let duration: TimeInterval
    /// Whether response was streamed
    let wasStreaming: Bool
}

/// A parsed SSE (Server-Sent Events) event
struct SSEEvent: Codable, Equatable {
    /// Event type (message, error, etc.)
    let type: String
    /// Event data
    let data: String
    /// Event ID (if any)
    let id: String?
    /// Retry interval in milliseconds (if any)
    let retry: Int?
}

/// Simple logger for DirectWebAPIClient diagnostics
private struct DirectWebAPIClientLogger {
    private let prefix = "[DirectWebAPIClient]"

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

/// Direct API client for sending messages to web chat providers.
///
/// Sends HTTP requests directly using URLSession with cookies from WKWebView,
/// bypassing DOM automation entirely.
///
/// ## Usage
/// ```swift
/// let cookies = await bridge.cookies()
/// let result = await DirectWebAPIClient.send(
///     message: "Hello!",
///     endpoint: endpoint,
///     cookies: cookies
/// )
/// if result.success {
///     print("Response: \(result.response ?? "")")
/// }
/// ```
///
/// ## Flow
/// 1. Extract cookies from WKWebView
/// 2. Build URLRequest from endpoint + cookies + message
/// 3. Send via URLSession
/// 4. Handle response (JSON, SSE, etc.)
/// 5. Return DirectAPIResult
///
/// ## Error Handling
/// - 401 Unauthorized → token expired
/// - 403 Forbidden → CSRF token expired
/// - 429 Too Many Requests → rate limited
/// - 500+ → server error
/// - Timeout → network issue
/// - SSL pinning → use browser fallback
enum DirectWebAPIClient {

    /// Default request timeout in seconds
    static let defaultTimeout: TimeInterval = 60

    /// Maximum response body size in bytes
    static let maxResponseBodySize = 1024 * 1024 // 1MB

    /// Logger for diagnostics
    private static let logger = DirectWebAPIClientLogger()

    // MARK: - Public API

    /// Send a message directly via API.
    ///
    /// - Parameters:
    ///   - message: Message to send
    ///   - endpoint: Chat API endpoint
    ///   - cookies: Browser cookies
    ///   - timeout: Request timeout (default: 60s)
    /// - Returns: API result with response or error
    ///
    /// ## Flow
    /// 1. Build URLRequest from endpoint
    /// 2. Add cookies and auth tokens
    /// 3. Send via URLSession
    /// 4. Parse response
    /// 5. Handle errors
    public static func send(
        message: String,
        endpoint: ChatAPIEndpoint,
        cookies: [BrowserCookie],
        timeout: TimeInterval = defaultTimeout
    ) async -> DirectAPIResult {
        let startTime = Date()
        let request = NetworkInterceptor.buildDirectRequest(
            endpoint: endpoint, cookies: cookies, message: message
        )
        
        logger.log("DirectWebAPIClient.send: url=\(request.url?.absoluteString ?? "nil"), method=\(request.httpMethod ?? "nil"), body=\(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "nil")")

        do {
            logger.log("DirectWebAPIClient.send: starting URLSession request")
            let (data, response) = try await URLSession.shared.data(for: request)
            logger.log("DirectWebAPIClient.send: received response")
            let duration = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                return DirectAPIResult(
                    success: false, response: nil,
                    error: "Invalid response type",
                    statusCode: 0, headers: [:],
                    duration: duration, wasStreaming: false
                )
            }

            let responseBody = String(data: data, encoding: .utf8)
            let responseHeaders = httpResponse.allHeaderFields as? [String: String] ?? [:]

            let success = (200...299).contains(httpResponse.statusCode)

            logger.log("DirectWebAPIClient.send: status=\(httpResponse.statusCode), success=\(success), duration=\(duration)")

            return DirectAPIResult(
                success: success,
                response: responseBody,
                error: success ? nil : "HTTP \(httpResponse.statusCode)",
                statusCode: httpResponse.statusCode,
                headers: responseHeaders,
                duration: duration,
                wasStreaming: false
            )
        } catch let error as URLError {
            let duration = Date().timeIntervalSince(startTime)
            logger.log("DirectWebAPIClient.send: URLError=\(error)")
            return DirectAPIResult(
                success: false, response: nil,
                error: "Network error: \(error.localizedDescription)",
                statusCode: 0, headers: [:],
                duration: duration, wasStreaming: false
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.log("DirectWebAPIClient.send: Error=\(error)")
            return DirectAPIResult(
                success: false, response: nil,
                error: "Error: \(error.localizedDescription)",
                statusCode: 0, headers: [:],
                duration: duration, wasStreaming: false
            )
        }
    }

    /// Send a message and stream the response via SSE.
    ///
    /// - Parameters:
    ///   - message: Message to send
    ///   - endpoint: Chat API endpoint
    ///   - cookies: Browser cookies
    ///   - onChunk: Called for each SSE event
    /// - Returns: API result with complete response
    ///
    /// ## SSE Format
    /// ```
    /// data: {"choices":[{"delta":{"content":"Hello"}}]}
    ///
    /// data: {"choices":[{"delta":{"content":" world"}}]}
    ///
    /// data: [DONE]
    /// ```
    public static func stream(
        message: String,
        endpoint: ChatAPIEndpoint,
        cookies: [BrowserCookie],
        onChunk: @escaping (SSEEvent) -> Void
    ) async -> DirectAPIResult {
        let startTime = Date()
        let request = NetworkInterceptor.buildDirectRequest(
            endpoint: endpoint, cookies: cookies, message: message
        )

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let duration = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                return DirectAPIResult(
                    success: false, response: nil,
                    error: "Invalid response type",
                    statusCode: 0, headers: [:],
                    duration: duration, wasStreaming: true
                )
            }

            let responseHeaders = httpResponse.allHeaderFields as? [String: String] ?? [:]
            var fullResponse = ""
            var buffer = ""

            for try await byte in bytes {
                guard let char = String(bytes: [byte], encoding: .utf8) else { continue }
                buffer.append(char)

                // Process complete SSE events
                while let range = buffer.range(of: "\n\n") {
                    let eventStr = String(buffer[buffer.startIndex..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])

                    if let event = parseSSEEvent(eventStr) {
                        onChunk(event)
                        if event.data == "[DONE]" {
                            break
                        }
                        fullResponse += event.data
                    }
                }
            }

            let success = (200...299).contains(httpResponse.statusCode)

            return DirectAPIResult(
                success: success,
                response: fullResponse.isEmpty ? nil : fullResponse,
                error: success ? nil : "HTTP \(httpResponse.statusCode)",
                statusCode: httpResponse.statusCode,
                headers: responseHeaders,
                duration: duration,
                wasStreaming: true
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return DirectAPIResult(
                success: false, response: nil,
                error: "Stream error: \(error.localizedDescription)",
                statusCode: 0, headers: [:],
                duration: duration, wasStreaming: true
            )
        }
    }

    /// Extract cookies from HTTPCookie array.
    ///
    /// - Parameter cookies: HTTP cookies
    /// - Returns: Cookie header value ("name1=value1; name2=value2")
    public static func extractCookies(from cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// Convert BrowserCookie array to HTTPCookie array.
    ///
    /// - Parameter browserCookies: Browser cookies from WKWebView
    /// - Returns: HTTPCookie array for URLSession
    public static func convertCookies(_ browserCookies: [BrowserCookie]) -> [HTTPCookie] {
        browserCookies.compactMap { cookie in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path
            ]
            if let expires = cookie.expiresEpoch {
                properties[.expires] = Date(timeIntervalSince1970: expires)
            }
            return HTTPCookie(properties: properties)
        }
    }

    /// Parse SSE event string into SSEEvent.
    ///
    /// - Parameter eventStr: Raw SSE event string
    /// - Returns: Parsed SSEEvent
    ///
    /// ## SSE Format
    /// ```
    /// event: message
    /// data: {"choices":[{"delta":{"content":"Hello"}}]}
    /// id: evt_123
    /// retry: 5000
    /// ```
    public static func parseSSEEvent(_ eventStr: String) -> SSEEvent? {
        let lines = eventStr.components(separatedBy: "\n")
        var eventType = "message"
        var dataParts: [String] = []
        var eventID: String?
        var retry: Int?

        for line in lines {
            if line.hasPrefix("event:") {
                eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                dataParts.append(data)
            } else if line.hasPrefix("id:") {
                eventID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("retry:") {
                retry = Int(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
            }
        }

        let data = dataParts.joined(separator: "\n")
        guard !data.isEmpty else { return nil }

        return SSEEvent(type: eventType, data: data, id: eventID, retry: retry)
    }

    /// Extract auth token from headers.
    ///
    /// - Parameters:
    ///   - headers: Response headers
    ///   - headerName: Header to extract from (default: "Authorization")
    /// - Returns: Auth token value (without "Bearer " prefix)
    public static func extractToken(from headers: [String: String], headerName: String = "Authorization") -> String? {
        guard let header = headers[headerName] else { return nil }
        if header.hasPrefix("Bearer ") {
            return String(header.dropFirst(7))
        }
        return header
    }

    /// Extract auth token from cookies.
    ///
    /// - Parameters:
    ///   - cookies: Browser cookies
    ///   - tokenName: Cookie name (e.g., "session_token")
    /// - Returns: Token value
    public static func extractToken(from cookies: [BrowserCookie], tokenName: String) -> String? {
        cookies.first { $0.name == tokenName }?.value
    }
}
