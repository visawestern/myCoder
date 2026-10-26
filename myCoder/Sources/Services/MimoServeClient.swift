import Foundation

// MARK: - Endpoint

enum MimoEndpoint {
    case health
    case projectCurrent
    case sessions
    case sessionStatus(String)
    case configProviders
    case fileContent(String)
    case fileStatus(String)
    case syncStart
    case syncReplay
    case syncHistory
    case vcsDiff(directory: String?, mode: VcsDiffMode)
    case globalConfig
    case createSession
    case sessionMessages(String)
    case sessionMessagesPage(String, limit: Int)
    case sessionPrompt(String)
    case sessionAbort(String)
    case questionReply(String)

    var path: String {
        switch self {
        case .health:
            return "/global/health"
        case .projectCurrent:
            return "/project/current"
        case .sessions:
            return "/experimental/session"
        case .sessionStatus(let id):
            return "/session/status/\(id)"
        case .configProviders:
            return "/config/providers"
        case .fileContent:
            return "/file/content"
        case .fileStatus:
            return "/file/status"
        case .syncStart:
            return "/sync/start"
        case .syncReplay:
            return "/sync/replay"
        case .syncHistory:
            return "/sync/history"
        case .vcsDiff:
            return "/vcs/diff"
        case .globalConfig:
            return "/global/config"
        case .createSession:
            return "/session"
        case .sessionMessages(let id):
            return "/session/\(id)/message"
        case .sessionMessagesPage(let id, _):
            return "/session/\(id)/message"
        case .sessionPrompt(let id):
            return "/session/\(id)/message"
        case .sessionAbort(let id):
            return "/session/\(id)/abort"
        case .questionReply(let requestID):
            return "/question/\(requestID)/reply"
        }
    }

    var method: String {
        switch self {
        case .syncStart, .createSession, .sessionPrompt, .sessionAbort, .questionReply:
            return "POST"
        default:
            return "GET"
        }
    }

    func queryItems() -> [URLQueryItem]? {
        switch self {
        case .fileContent(let path):
            return [URLQueryItem(name: "path", value: path)]
        case .fileStatus(let path):
            return [URLQueryItem(name: "path", value: path)]
        case .vcsDiff(let directory, let mode):
            var items = [URLQueryItem(name: "mode", value: mode.rawValue)]
            if let directory, !directory.isEmpty {
                items.append(URLQueryItem(name: "directory", value: directory))
            }
            return items
        case .sessionMessagesPage(_, let limit):
            return [URLQueryItem(name: "limit", value: String(limit))]
        default:
            return nil
        }
    }
}

enum VcsDiffMode: String, Sendable {
    case git
    case branch
}

// MARK: - Client

class MimoServeClient {
    let host: String
    let port: Int

    private let session: URLSession
    private let decoder: JSONDecoder

    init(host: String = "127.0.0.1", port: Int = 0) {
        self.host = host
        self.port = port
        let config = URLSessionConfiguration.default
        // Audit 2026-09-11: loading a chat used to hang up to 5 MINUTES on a
        // dead server (standalone chats looked permanently empty) before the
        // local-DB fallback kicked in. 10s is plenty for a local server and
        // fails over fast when none is running.
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    var baseURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        return components.url!
    }

    func url(for endpoint: MimoEndpoint) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)!
        components.queryItems = endpoint.queryItems()
        return components.url!
    }

    // MARK: - API Methods

    func health() async throws -> MimoHealthResponse {
        try await get(.health)
    }

    func projectCurrent() async throws -> MimoProjectResponse {
        try await get(.projectCurrent)
    }

    func sessions() async throws -> [MimoSessionResponse] {
        try await get(.sessions)
    }

    func sessionStatus(id: String) async throws -> MimoSessionStatusResponse {
        try await get(.sessionStatus(id))
    }

    func providers() async throws -> [MimoProviderResponse] {
        let response: MimoProvidersWrapper = try await get(.configProviders)
        return response.providers
    }

    func fileContent(path: String) async throws -> MimoFileContentResponse {
        try await get(.fileContent(path))
    }

    func fileStatus(path: String) async throws -> MimoFileStatusResponse {
        try await get(.fileStatus(path))
    }

    func syncStart() async throws -> MimoSessionResponse {
        try await post(.syncStart)
    }

    func syncStart(message: String) async throws -> MimoSessionResponse {
        let response: SyncStartResponse = try await postSyncStart(body: SyncStartRequest(prompt: message))
        return response.session ?? MimoSessionResponse(
            id: UUID().uuidString, slug: "", projectID: "", directory: "",
            title: message, version: "1.0", summary: nil,
            time: MimoTimeRange(created: Int64(Date().timeIntervalSince1970), updated: Int64(Date().timeIntervalSince1970)),
            project: nil, parentID: nil
        )
    }

    func syncStart(message: String, files: [String]) async throws -> MimoSessionResponse {
        let response: SyncStartResponse = try await postSyncStart(body: SyncStartRequest(prompt: message, files: files))
        return response.session ?? MimoSessionResponse(
            id: UUID().uuidString, slug: "", projectID: "", directory: "",
            title: message, version: "1.0", summary: nil,
            time: MimoTimeRange(created: Int64(Date().timeIntervalSince1970), updated: Int64(Date().timeIntervalSince1970)),
            project: nil, parentID: nil
        )
    }
    
    // MARK: - Real Session API
    
    func createSession(title: String) async throws -> MimoSessionCreateResponse {
        try await post(.createSession, body: ["title": title])
    }
    
    func sendMessage(
        sessionID: String,
        parts: [[String: Any]],
        options: MessageSendOptions,
        parameters: ModelCallParameters = ModelCallParameters()
    ) async throws -> [MimoMessageResponse] {
        let body = options.requestBody(parts: parts, parameters: parameters)
        let data = try JSONSerialization.data(withJSONObject: body)
        let url = url(for: .sessionPrompt(sessionID))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        // Model generation is long-running: the session-wide 10s failover
        // timeout does not apply — a full agent answer can take minutes.
        request.timeoutInterval = 600
        
        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            if ServeTransportFailureLogic.isConnectionFailure(error) {
                throw MimoServeError.connectionFailed
            }
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code == 409 {
                throw MimoServeError.sessionBusy
            }
            throw MimoServeError.httpError(
                statusCode: code,
                message: Self.errorMessage(from: responseData)
            )
        }
        
        let text = String(data: responseData, encoding: .utf8) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "true" { return [] }

        if let message = try? decoder.decode(MimoMessageResponse.self, from: responseData) {
            return [message]
        }
        if let messages = try? decoder.decode([MimoMessageResponse].self, from: responseData) {
            return messages
        }

        // Be tolerant of compatible serve implementations that wrap the
        // response instead of returning a bare message/array.
        if let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            for key in ["messages", "data"] {
                if let value = object[key],
                   JSONSerialization.isValidJSONObject(value),
                   let encoded = try? JSONSerialization.data(withJSONObject: value),
                   let decoded = try? decoder.decode([MimoMessageResponse].self, from: encoded) {
                    return decoded
                }
            }
            if let value = object["message"],
               JSONSerialization.isValidJSONObject(value),
               let encoded = try? JSONSerialization.data(withJSONObject: value),
               let decoded = try? decoder.decode(MimoMessageResponse.self, from: encoded) {
                return [decoded]
            }
            if let answer = object["text"] as? String, !answer.isEmpty {
                let info = MimoMessageInfo(id: nil, role: "assistant", agent: nil,
                                           modelID: nil, providerID: nil, variant: nil, model: nil)
                return [MimoMessageResponse(info: info, parts: [.text(answer)])]
            }
        }
        return []
    }

    func replyToQuestion(requestID: String, answers: [[String]]) async throws {
        let url = url(for: .questionReply(requestID))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["answers": answers])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MimoServeError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
                message: Self.errorMessage(from: data)
            )
        }
    }

    func abortSession(id: String) async throws {
        let url = url(for: .sessionAbort(id))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MimoServeError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
    
    func getMessages(
        sessionID: String,
        limit: Int? = nil
    ) async throws -> [MimoMessageResponse] {
        let endpoint: MimoEndpoint
        if let limit {
            endpoint = .sessionMessagesPage(sessionID, limit: limit)
        } else {
            endpoint = .sessionMessages(sessionID)
        }
        let url = url(for: endpoint)
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MimoServeError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try decoder.decode([MimoMessageResponse].self, from: data)
    }
    
    private func postSyncStart<B: Encodable>(body: B) async throws -> SyncStartResponse {
        let url = url(for: .syncStart)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MimoServeError.httpError(statusCode: code)
        }
        
        let text = String(data: data, encoding: .utf8) ?? ""
        if text == "true" {
            return SyncStartResponse(success: true)
        }
        
        return try decoder.decode(SyncStartResponse.self, from: data)
    }

    func vcsDiff(directory: String? = nil, mode: VcsDiffMode = .git) async throws -> MimoVcsDiffResponse {
        try await get(.vcsDiff(directory: directory, mode: mode))
    }

    func globalConfig() async throws -> MimoConfigResponse {
        try await get(.globalConfig)
    }

    func updateGlobalConfig(_ patch: [String: Any]) async throws -> MimoConfigResponse {
        let url = url(for: .globalConfig)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: patch)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MimoServeError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try decoder.decode(MimoConfigResponse.self, from: data)
    }

    // MARK: - Private

    private func get<T: Decodable>(_ endpoint: MimoEndpoint) async throws -> T {
        let url = url(for: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MimoServeError.httpError(statusCode: code)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ endpoint: MimoEndpoint) async throws -> T {
        let url = url(for: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MimoServeError.httpError(statusCode: code)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ endpoint: MimoEndpoint, body: B) async throws -> T {
        let url = url(for: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MimoServeError.httpError(statusCode: code)
        }

        return try decoder.decode(T.self, from: data)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let errors = json["error"] as? [[String: Any]], let first = errors.first {
            if let message = first["message"] as? String, !message.isEmpty {
                if let note = first["note"] as? String, !note.isEmpty {
                    return "\(message) (\(note))"
                }
                return message
            }
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }
}

// MARK: - Errors

enum MimoServeError: Error, LocalizedError {
    case httpError(statusCode: Int, message: String? = nil)
    case decodingError(Error)
    case connectionFailed
    case emptyResponse
    case sessionBusy

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let message):
            if let message, !message.isEmpty {
                return "HTTP error \(code): \(message)"
            }
            return "HTTP error \(code)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .connectionFailed:
            return "Connection failed"
        case .emptyResponse:
            return ProviderResponseValidationLogic.emptyCompletionMessage
        case .sessionBusy:
            return "Session is busy processing another request. Please wait or stop the current generation."
        }
    }
}
