import Testing
import Foundation
@testable import myCoder

private var liveTestsEnabled: Bool {
    ProcessInfo.processInfo.environment["MIMO_LIVE_TESTS"] == "1"
}

@Suite("Live API Integration", .serialized)
struct LiveAPIIntegrationTests {
    
    let baseURL = "http://127.0.0.1:4096"
    
    private func healthCheck() async throws -> Bool {
        let url = URL(string: "\(baseURL)/global/health")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["healthy"] as? Bool == true
    }
    
    private func createSession(title: String) async throws -> String {
        let url = URL(string: "\(baseURL)/session")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["id"] as! String
    }
    
    private func sendPrompt(sessionID: String, text: String) async throws -> String {
        let url = URL(string: "\(baseURL)/session/\(sessionID)/message")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["parts": [["type": "text", "text": text]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(for: request)
        
        let text = String(data: data, encoding: .utf8) ?? ""
        if text == "true" { return "" }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let parts = json["parts"] as? [[String: Any]] {
            for part in parts {
                if part["type"] as? String == "text",
                   let t = part["text"] as? String {
                    return t
                }
            }
        }
        return text
    }
    
    // MARK: - Tests
    
    @Test("Server is alive")
    func serverHealth() async throws {
        guard liveTestsEnabled else { return }
        let healthy = try await healthCheck()
        #expect(healthy == true)
    }
    
    @Test("Send question and get real response")
    func sendQuestion() async throws {
        guard liveTestsEnabled else { return }
        guard try await healthCheck() else {
            throw TestError.serverNotRunning
        }
        
        let sessionID = try await createSession(title: "Math test")
        let response = try await sendPrompt(sessionID: sessionID, text: "What is 2+2? Reply with just the number.")
        
        #expect(!response.isEmpty)
        #expect(response.contains("4"))
    }
    
    @Test("Send question and get text response about a topic")
    func sendTopicQuestion() async throws {
        guard liveTestsEnabled else { return }
        guard try await healthCheck() else {
            throw TestError.serverNotRunning
        }
        
        let sessionID = try await createSession(title: "Topic test")
        let response = try await sendPrompt(sessionID: sessionID, text: "What programming language is Swift? Reply in one sentence.")
        
        #expect(!response.isEmpty)
        #expect(response.lowercased().contains("swift") || response.lowercased().contains("programming"))
    }
    
    @Test("Send image file and get response")
    func sendImageFile() async throws {
        guard liveTestsEnabled else { return }
        guard try await healthCheck() else {
            throw TestError.serverNotRunning
        }
        
        let sessionID = try await createSession(title: "Image test")
        let imagePath = "/Users/apple/projects/mimo-macos/screenshot_1.png"
        
        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw TestError.fileNotFound(imagePath)
        }
        
        let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let base64Image = imageData.base64EncodedString()
        
        let body: [String: Any] = [
            "parts": [
                ["type": "text", "text": "What do you see in this image? Reply briefly."],
                ["type": "image", "mediaType": "image/png", "data": base64Image]
            ]
        ]
        
        let url = URL(string: "\(baseURL)/session/\(sessionID)/message")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(for: request)
        
        let responseText = String(data: data, encoding: .utf8) ?? ""
        
        if responseText != "true" {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let parts = json["parts"] as? [[String: Any]] {
                for part in parts {
                    if part["type"] as? String == "text",
                       let t = part["text"] as? String {
                        #expect(!t.isEmpty)
                        return
                    }
                }
            }
            #expect(!responseText.isEmpty)
        }
    }
    
    @Test("Send text file and get response")
    func sendTextFile() async throws {
        guard liveTestsEnabled else { return }
        guard try await healthCheck() else {
            throw TestError.serverNotRunning
        }
        
        let sessionID = try await createSession(title: "Text file test")
        
        let fileContent = "func hello() { print(\"Hello World\") }"
        let base64Content = Data(fileContent.utf8).base64EncodedString()
        
        let body: [String: Any] = [
            "parts": [
                ["type": "text", "text": "What does this Swift code do? Reply briefly."],
                ["type": "file", "mediaType": "text/plain", "filename": "hello.swift", "data": base64Content]
            ]
        ]
        
        let url = URL(string: "\(baseURL)/session/\(sessionID)/message")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(for: request)
        
        let responseText = String(data: data, encoding: .utf8) ?? ""
        
        if responseText != "true" {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let parts = json["parts"] as? [[String: Any]] {
                for part in parts {
                    if part["type"] as? String == "text",
                       let t = part["text"] as? String {
                        #expect(!t.isEmpty)
                        return
                    }
                }
            }
            #expect(!responseText.isEmpty)
        }
    }
    
    @Test("Session message history returns messages")
    func messageHistory() async throws {
        guard liveTestsEnabled else { return }
        guard try await healthCheck() else {
            throw TestError.serverNotRunning
        }
        
        let sessionID = try await createSession(title: "History test")
        _ = try await sendPrompt(sessionID: sessionID, text: "Say hello")
        
        let url = URL(string: "\(baseURL)/session/\(sessionID)/message")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let messages = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        
        #expect(messages != nil)
        #expect(messages!.count >= 1)
    }
    
    @Test("Models list is not empty")
    func modelsList() async throws {
        guard liveTestsEnabled else { return }
        guard try await healthCheck() else {
            throw TestError.serverNotRunning
        }

        let url = URL(string: "\(baseURL)/config/providers")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let providers = json?["providers"] as? [[String: Any]]

        #expect(providers != nil)
        #expect(providers!.count >= 1)
    }

    @Test("Nested model payload accepted by server")
    func nestedModelPayload() async throws {
        guard liveTestsEnabled else { return }
        guard try await healthCheck() else {
            throw TestError.serverNotRunning
        }

        let sessionID = try await createSession(title: "Nested model test")
        let url = URL(string: "\(baseURL)/session/\(sessionID)/message")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "parts": [["type": "text", "text": "Reply with ok only."]],
            "agent": "build",
            "model": ["providerID": "mimo", "modelID": "mycoder-auto-free"],
            "variant": "low"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let info = json?["info"] as? [String: Any]
        #expect(info?["agent"] as? String == "build")
        #expect(info?["modelID"] as? String == "mycoder-auto-free")
    }

    @Test("PATCH global config updates permission")
    func patchGlobalPermission() async throws {
        guard liveTestsEnabled else { return }
        guard try await healthCheck() else {
            throw TestError.serverNotRunning
        }

        let url = URL(string: "\(baseURL)/global/config")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["permission": ["edit": "ask"]])

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        #expect(http?.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let permission = json?["permission"] as? [String: Any]
        #expect(permission?["edit"] as? String == "ask")
    }
}

enum TestError: Error, LocalizedError {
    case serverNotRunning
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .serverNotRunning: return "Server not running on port 4096"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }
}
