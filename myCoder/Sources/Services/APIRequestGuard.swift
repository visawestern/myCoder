import Foundation
import Security

/// Проверка входящего запроса локального API. Чистые функции — легко тестировать.
enum APIRequestGuard {
    enum Verdict: Equatable {
        case allowed
        case forbidden(String)
    }

    /// Разбирает блок заголовков HTTP в словарь (имена в нижнем регистре).
    static func parseHeaders(_ headerBlock: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in headerBlock.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[name] = value
        }
        return result
    }

    static func validate(headers: [String: String], token: String, port: UInt16) -> Verdict {
        // 1. Host: только loopback (защита от DNS-rebinding).
        let host = (headers["host"] ?? "").lowercased()
        guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else {
            return .forbidden("bad host")
        }
        // 2. Браузерные запросы несут Origin. Наш клиент (curl, тесты) его не шлёт.
        if headers["origin"] != nil { return .forbidden("browser origin") }
        // 3. Токен.
        let header = headers["authorization"] ?? ""
        let provided = header.hasPrefix("Bearer ") ? String(header.dropFirst(7)) : ""
        guard constantTimeEquals(provided, token) else { return .forbidden("bad token") }
        return .allowed
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8)
        let y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString + UUID().uuidString  // запасной вариант
    }
}

/// Токен лежит в ~/.mycoder/api-token с правами 0600.
enum APITokenStore {
    static func tokenFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        MyCoderPaths.appDir(homeDirectory: homeDirectory).appendingPathComponent("api-token")
    }

    static func loadOrCreate(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let url = tokenFileURL(homeDirectory: homeDirectory)
        if let existing = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 32 {
            return existing
        }
        let token = APIRequestGuard.makeToken()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? token.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }
}
