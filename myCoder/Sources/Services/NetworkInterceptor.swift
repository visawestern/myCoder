import Foundation

/// A single captured network request from the browser.
struct CapturedRequest: Codable, Equatable {
    /// Request URL
    let url: String
    /// HTTP method (GET, POST, etc.)
    let method: String
    /// Request headers
    let headers: [String: String]
    /// Request body (if any)
    let body: String?
    /// When the request was captured
    let timestamp: Date
    /// Internal tracking ID
    let requestID: String
}

/// A single captured network response from the browser.
struct CapturedResponse: Codable, Equatable {
    /// Response URL
    let url: String
    /// HTTP status code
    let status: Int
    /// Response headers
    let headers: [String: String]
    /// Response body (if any)
    let body: String?
    /// Associated request ID
    let requestID: String
    /// When the response was captured
    let timestamp: Date
}

/// Identified chat API endpoint extracted from captured requests.
struct ChatAPIEndpoint: Codable, Equatable {
    /// Full API URL
    let url: String
    /// HTTP method
    let method: String
    /// Required headers
    let headers: [String: String]
    /// Body template with placeholder: {{message}}
    let bodyTemplate: String
    /// Whether this is a streaming endpoint (SSE)
    let isStreaming: Bool
    /// Content type
    let contentType: String
    /// Auth token location (header name or cookie name)
    let authLocation: String?
    /// Auth token value
    let authToken: String?
}

/// Network request interceptor that captures XHR/fetch requests from WKWebView.
///
/// Injects JavaScript to override `XMLHttpRequest.prototype.open/send` and
/// `window.fetch`, capturing all network traffic for analysis.
///
/// ## Usage
/// ```swift
/// // Install interceptor
/// await NetworkInterceptor.install(bridge: bridge)
///
/// // ... user interacts with web chat ...
///
/// // Capture requests
/// let requests = await NetworkInterceptor.captureRequests(bridge: bridge)
/// let responses = await NetworkInterceptor.captureResponses(bridge: bridge)
///
/// // Find chat API
/// if let endpoint = NetworkInterceptor.findChatAPI(requests: requests) {
///     let directRequest = NetworkInterceptor.buildDirectRequest(
///         endpoint: endpoint, cookies: cookies, message: "Hello"
///     )
/// }
/// ```
///
/// ## JavaScript Injection
/// The interceptor overrides:
/// - `XMLHttpRequest.prototype.open` → captures URL + method
/// - `XMLHttpRequest.prototype.send` → captures body
/// - `XMLHttpRequest.prototype.setRequestHeader` → captures headers
/// - `XMLHttpRequest.prototype.onload` → captures response
/// - `Window.fetch` → captures fetch requests/responses
///
/// All captured data is stored in `window.__mycoder_requests` and
/// `window.__mycoder_responses` arrays.
///
/// ## API Discovery
/// `findChatAPI()` identifies chat endpoints by:
/// 1. POST method
/// 2. JSON Content-Type
/// 3. Body contains message/content/prompt fields
/// 4. URL contains chat/send/message/api paths
enum NetworkInterceptor {

    // MARK: - Public API

    /// Install the network interceptor by injecting JavaScript.
    ///
    /// - Parameter bridge: Browser automation bridge
    ///
    /// ## JS Injected
    /// Overrides XMLHttpRequest and fetch to capture all network traffic.
    /// Data is stored in window.__mycoder_requests and window.__mycoder_responses.
    public static func install(bridge: BrowserAutomationBridge) async {
        let js = """
        (function(){
            if (window.__mycoder_interceptor_installed) return;
            window.__mycoder_interceptor_installed = true;
            window.__mycoder_requests = [];
            window.__mycoder_responses = [];
            window.__mycoder_request_counter = 0;

            // Override XMLHttpRequest
            var OrigXHR = window.XMLHttpRequest;
            window.XMLHttpRequest = function() {
                var xhr = new OrigXHR();
                var origOpen = xhr.open;
                var origSend = xhr.send;
                var origSetRequestHeader = xhr.setRequestHeader;
                var requestId = 'xhr_' + (++window.__mycoder_request_counter);

                var capturedHeaders = {};

                xhr.open = function(method, url) {
                    this.__mycoder_method = method;
                    this.__mycoder_url = url;
                    this.__mycoder_request_id = requestId;
                    capturedHeaders = {};
                    return origOpen.apply(this, arguments);
                };

                xhr.setRequestHeader = function(name, value) {
                    capturedHeaders[name] = value;
                    return origSetRequestHeader.apply(this, arguments);
                };

                xhr.send = function(body) {
                    var entry = {
                        requestID: requestId,
                        url: this.__mycoder_url || '',
                        method: this.__mycoder_method || 'GET',
                        headers: Object.assign({}, capturedHeaders),
                        body: body ? (typeof body === 'string' ? body : JSON.stringify(body)) : null,
                        timestamp: new Date().toISOString()
                    };
                    window.__mycoder_requests.push(entry);

                    var self = this;
                    this.addEventListener('load', function() {
                        var respEntry = {
                            requestID: requestId,
                            url: self.__mycoder_url || '',
                            status: self.status,
                            headers: parseHeaders(self.getAllResponseHeaders()),
                            body: self.responseText ? self.responseText.substring(0, 10000) : null,
                            timestamp: new Date().toISOString()
                        };
                        window.__mycoder_responses.push(respEntry);
                    });

                    return origSend.apply(this, arguments);
                };

                return xhr;
            };

            // Override fetch
            var origFetch = window.fetch;
            window.fetch = function(input, init) {
                var url = typeof input === 'string' ? input : (input.url || '');
                var method = (init && init.method) || 'GET';
                var headers = {};
                var body = null;
                var fetchId = 'fetch_' + (++window.__mycoder_request_counter);

                if (init) {
                    if (init.headers) {
                        if (init.headers instanceof Headers) {
                            init.headers.forEach(function(value, name) {
                                headers[name] = value;
                            });
                        } else if (typeof init.headers === 'object') {
                            headers = Object.assign({}, init.headers);
                        }
                    }
                    body = init.body ? (typeof init.body === 'string' ? init.body : JSON.stringify(init.body)) : null;
                }

                var entry = {
                    requestID: fetchId,
                    url: url,
                    method: method.toUpperCase(),
                    headers: headers,
                    body: body,
                    timestamp: new Date().toISOString()
                };
                window.__mycoder_requests.push(entry);

                return origFetch.apply(this, arguments).then(function(response) {
                    var cloned = response.clone();
                    cloned.text().then(function(text) {
                        var respEntry = {
                            requestID: fetchId,
                            url: url,
                            status: response.status,
                            headers: {},
                            body: text.substring(0, 10000),
                            timestamp: new Date().toISOString()
                        };
                        response.headers.forEach(function(value, name) {
                            respEntry.headers[name] = value;
                        });
                        window.__mycoder_responses.push(respEntry);
                    });
                    return response;
                });
            };

            function parseHeaders(headerStr) {
                var headers = {};
                if (!headerStr) return headers;
                headerStr.split('\\r\\n').forEach(function(line) {
                    var parts = line.split(': ');
                    if (parts.length >= 2) {
                        headers[parts[0]] = parts.slice(1).join(': ');
                    }
                });
                return headers;
            }
        })();
        """
        let _ = try? await bridge.evaluateJS(js)
    }

    /// Capture all intercepted requests from the browser.
    ///
    /// - Parameter bridge: Browser automation bridge
    /// - Returns: Array of captured requests, sorted by timestamp
    public static func captureRequests(bridge: BrowserAutomationBridge) async -> [CapturedRequest] {
        let js = "JSON.stringify(window.__mycoder_requests || [])"
        guard let json = (try? await bridge.evaluateJS(js)) as? String,
              let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return raw.compactMap { dict in
            guard let url = dict["url"] as? String,
                  let method = dict["method"] as? String,
                  let requestID = dict["requestID"] as? String else { return nil }

            let headers = dict["headers"] as? [String: String] ?? [:]
            let body = dict["body"] as? String
            let timestamp: Date
            if let ts = dict["timestamp"] as? String {
                timestamp = ISO8601DateFormatter().date(from: ts) ?? Date()
            } else {
                timestamp = Date()
            }

            return CapturedRequest(
                url: url,
                method: method,
                headers: headers,
                body: body,
                timestamp: timestamp,
                requestID: requestID
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }

    /// Capture all intercepted responses from the browser.
    ///
    /// - Parameter bridge: Browser automation bridge
    /// - Returns: Array of captured responses, sorted by timestamp
    public static func captureResponses(bridge: BrowserAutomationBridge) async -> [CapturedResponse] {
        let js = "JSON.stringify(window.__mycoder_responses || [])"
        guard let json = (try? await bridge.evaluateJS(js)) as? String,
              let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return raw.compactMap { dict in
            guard let url = dict["url"] as? String,
                  let status = dict["status"] as? Int,
                  let requestID = dict["requestID"] as? String else { return nil }

            let headers = dict["headers"] as? [String: String] ?? [:]
            let body = dict["body"] as? String
            let timestamp: Date
            if let ts = dict["timestamp"] as? String {
                timestamp = ISO8601DateFormatter().date(from: ts) ?? Date()
            } else {
                timestamp = Date()
            }

            return CapturedResponse(
                url: url,
                status: status,
                headers: headers,
                body: body,
                requestID: requestID,
                timestamp: timestamp
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }

    /// Find chat API endpoint from captured requests.
    ///
    /// - Parameter requests: Captured requests
    /// - Returns: Chat API endpoint if found, nil otherwise
    ///
    /// ## Detection Logic
    /// 1. Filter POST requests with JSON Content-Type
    /// 2. Check body for message/content/prompt fields
    /// 3. Check URL for chat/send/message/api paths
    /// 4. Extract auth tokens from headers
    public static func findChatAPI(requests: [CapturedRequest]) -> ChatAPIEndpoint? {
        let postRequests = requests.filter { $0.method.uppercased() == "POST" }

        var candidates: [(request: CapturedRequest, score: Float)] = []

        for req in postRequests {
            // Round 30 quality gates:
            // (a) obvious non-chat endpoints (telemetry/status/log) must never
            // become the chat route — they previously won scoring via their
            // JSON bodies and produced garbage sends;
            // (b) relative URLs cannot be executed by URLSession
            // ("unsupported URL", -1002) — only absolute http(s) qualify.
            let urlLower = req.url.lowercased()
            let junkMarkers = ["users/status", "/users/", "telemetry", "tracking",
                               "/log", "/report", "/ping", "/health", "/feedback",
                               "/analytics",
                               // Audit 2026-09-09 (Kimi live): the account
                               // RefreshToken endpoint won scoring via /api/ +
                               // Bearer and SmartSend burned 2 attempts POSTing
                               // chat bodies at it (HTTP 520). Auth/session/
                               // account endpoints are never chat routes.
                               "refresh", "token", "/login", "/signin",
                               "/signup", "/auth", "/session", "/account",
                               "/user/", "/users", "/verify", "/captcha",
                               "/challenge", "/turnstile", "/sentinel",
                               // Audit 2026-09-09 (ChatGPT live): the
                               // telemetry endpoint chatgpt.com/ces/v1/t
                               // (Segment.io event stream) returned HTTP 200
                               // for a chat body and SmartSend declared the
                               // send a success while nothing reached the
                               // model. Telemetry/analytics/beacon endpoints
                               // are never chat routes.
                               "/ces/", "ces/v1", "segment", "/track",
                               "/beacon", "/collect", "/event", "analytics"]
            if junkMarkers.contains(where: { urlLower.contains($0) }) { continue }
            guard let parsed = URL(string: req.url),
                  let scheme = parsed.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  parsed.host != nil else { continue }

            var score: Float = 0

            // Check Content-Type
            let contentType = req.headers["Content-Type"] ?? req.headers["content-type"] ?? ""
            if contentType.contains("application/json") {
                score += 0.3
            } else if contentType.contains("text/plain") {
                score += 0.1
            }

            // Check body for message fields
            if let body = req.body {
                let bodyLower = body.lowercased()
                let messageFields = ["message", "content", "prompt", "query", "input", "text", "question"]
                for field in messageFields {
                    if bodyLower.contains("\"\(field)\"") || bodyLower.contains("\(field):") {
                        score += 0.2
                        break
                    }
                }
            }

            // Check URL for chat endpoints
            let chatPaths = ["/chat", "/send", "/message", "/api/", "/completions", "/generate", "/v1/", "/v2/"]
            for path in chatPaths {
                if urlLower.contains(path) {
                    score += 0.2
                    break
                }
            }

            // Check for streaming indicators
            let accept = req.headers["Accept"] ?? req.headers["accept"] ?? ""
            if accept.contains("text/event-stream") {
                score += 0.1
            }

            // Check for auth tokens
            let auth = req.headers["Authorization"] ?? req.headers["authorization"] ?? ""
            if auth.contains("Bearer ") {
                score += 0.1
            }

            if score > 0.3 {
                candidates.append((req, score))
            }
        }

        candidates.sort { $0.score > $1.score }

        // Audit 2026-09-09 (ChatGPT live): the telemetry endpoint
        // chatgpt.com/ces/v1/t returned HTTP 200 for a chat-shaped POST and
        // SmartSend declared success while the message never reached any
        // model. A candidate whose captured body has NO substitutable
        // message field cannot carry our text (buildDirectRequest would POST
        // the template verbatim) — skip it no matter its score.
        for candidate in candidates {
            let template = buildBodyTemplate(body: candidate.request.body)
            guard template.contains("{{message}}") else { continue }
            let best = candidate
            // (auth extraction + endpoint build below operate on `best`)

        // Extract auth info
        let authHeader = best.request.headers["Authorization"] ?? best.request.headers["authorization"]
        var authToken: String?
        var authLocation: String?

        if let auth = authHeader, auth.hasPrefix("Bearer ") {
            authToken = String(auth.dropFirst(7))
            authLocation = "Authorization"
        }

        // Check cookies
        if authToken == nil {
            let cookieHeader = best.request.headers["Cookie"] ?? best.request.headers["cookie"]
            if let cookie = cookieHeader {
                authToken = cookie
                authLocation = "Cookie"
            }
        }

        // Build body template
        let bodyTemplate = buildBodyTemplate(body: best.request.body)

        // Check if streaming
        let accept = best.request.headers["Accept"] ?? best.request.headers["accept"] ?? ""
        let isStreaming = accept.contains("text/event-stream")

        // Extract content type
        let contentType = best.request.headers["Content-Type"] ?? best.request.headers["content-type"] ?? "application/json"

        return ChatAPIEndpoint(
            url: best.request.url,
            method: best.request.method,
            headers: best.request.headers,
            bodyTemplate: bodyTemplate,
            isStreaming: isStreaming,
            contentType: contentType,
            authLocation: authLocation,
            authToken: authToken
        )
        }
        return nil
    }

    /// Build a direct URLRequest from an endpoint.
    ///
    /// - Parameters:
    ///   - endpoint: Chat API endpoint
    ///   - cookies: Browser cookies
    ///   - message: Message to send
    /// - Returns: Configured URLRequest
    public static func buildDirectRequest(
        endpoint: ChatAPIEndpoint,
        cookies: [BrowserCookie],
        message: String
    ) -> URLRequest {
        guard let url = URL(string: endpoint.url) else {
            return URLRequest(url: URL(string: "about:blank")!)
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method

        // Set headers
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Handle ConnectRPC endpoints (Kimi)
        let isConnectRPC = endpoint.url.contains("kimi.gateway.chat") || endpoint.url.contains("ChatService")
        
        // Ensure Content-Type is set
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            if isConnectRPC {
                request.setValue("application/connect+json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/connect+json", forHTTPHeaderField: "Accept")
            } else {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        // Set cookies
        if !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        // Set auth token
        if let token = endpoint.authToken, let location = endpoint.authLocation {
            if location == "Authorization" {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        // Build body
        let body: String
        if isConnectRPC {
            // Kimi ConnectRPC JSON format
            let connectBody: [String: Any] = [
                "message": [
                    "chat_id": "",  // Will be filled by server if empty
                    "type": 1,  // CHAT_TYPE_CHAT = 1
                    "message": message,
                    "tools": [],
                    "options": [
                        "model": "kimi",
                        "temperature": 0.7,
                        "top_p": 0.9
                    ],
                    "kimiplus_id": "",
                    "scenario": "",
                    "voice_id": "",
                    "enable_search": false,
                    "model": "kimi"
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: connectBody, options: []),
               let jsonString = String(data: data, encoding: .utf8) {
                body = jsonString
            } else {
                body = "{}"
            }
        } else {
            // Standard template replacement
            body = endpoint.bodyTemplate.replacingOccurrences(of: "{{message}}", with: message)
        }
        
        request.httpBody = body.data(using: .utf8)

        // Set timeout
        request.timeoutInterval = 60

        return request
    }

    // MARK: - Private Helpers

    /// Build a body template by replacing message content with placeholder
    private static func buildBodyTemplate(body: String?) -> String {
        guard let body = body else {
            return "{\"message\": \"{{message}}\"}"
        }

        // Try to parse as JSON and replace message field
        if let data = body.data(using: .utf8),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let messageFields = ["message", "content", "prompt", "query", "input", "text", "question"]
            for field in messageFields {
                if json[field] != nil {
                    json[field] = "{{message}}"
                    if let newData = try? JSONSerialization.data(withJSONObject: json),
                       let newBody = String(data: newData, encoding: .utf8) {
                        return newBody
                    }
                }
            }
        }

        // Fallback: replace common patterns
        var template = body
        let patterns = [
            "\"message\":\\s*\"[^\"]*\"": "\"message\": \"{{message}}\"",
            "\"content\":\\s*\"[^\"]*\"": "\"content\": \"{{message}}\"",
            "\"prompt\":\\s*\"[^\"]*\"": "\"prompt\": \"{{message}}\"",
            "\"query\":\\s*\"[^\"]*\"": "\"query\": \"{{message}}\"",
            "\"input\":\\s*\"[^\"]*\"": "\"input\": \"{{message}}\"",
            "\"text\":\\s*\"[^\"]*\"": "\"text\": \"{{message}}\"",
            "\"question\":\\s*\"[^\"]*\"": "\"question\": \"{{message}}\""
        ]

        for (pattern, replacement) in patterns {
            template = template.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return template
    }
}
