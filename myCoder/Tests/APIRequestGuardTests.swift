import Foundation
import Testing
@testable import myCoder

@Suite("APIRequestGuard")
struct APIRequestGuardTests {
    let token = String(repeating: "a", count: 64)

    @Test("валидный запрос проходит")
    func allowsValid() {
        let h = ["host": "127.0.0.1:8766", "authorization": "Bearer \(token)"]
        #expect(APIRequestGuard.validate(headers: h, token: token, port: 8766) == .allowed)
    }

    @Test("без токена — запрещено")
    func rejectsNoToken() {
        let h = ["host": "127.0.0.1:8766"]
        #expect(APIRequestGuard.validate(headers: h, token: token, port: 8766) != .allowed)
    }

    @Test("браузерный Origin запрещён даже с токеном")
    func rejectsOrigin() {
        let h = ["host": "127.0.0.1:8766", "origin": "http://evil.example", "authorization": "Bearer \(token)"]
        #expect(APIRequestGuard.validate(headers: h, token: token, port: 8766) != .allowed)
    }

    @Test("чужой Host (DNS-rebinding) запрещён")
    func rejectsForeignHost() {
        let h = ["host": "evil.example:8766", "authorization": "Bearer \(token)"]
        #expect(APIRequestGuard.validate(headers: h, token: token, port: 8766) != .allowed)
    }
}
