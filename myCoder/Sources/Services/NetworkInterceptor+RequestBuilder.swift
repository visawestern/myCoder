import Foundation

extension NetworkInterceptor {
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
    static func buildBodyTemplate(body: String?) -> String {
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
