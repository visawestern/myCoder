import Foundation

extension MyCoderAPIServer {
    // MARK: - Scroll API

    /// GET /api/scroll — report the live chat scroll state: offset, content
    /// range, whether the bottom is visible, the last command, and (with
    /// `?samples=1`) recent offset samples. This is the read side of the
    /// scroll diagnostics.
    func handleScroll(query: String = "") async -> String {
        let sampleLimit = query.components(separatedBy: "&")
            .first(where: { $0.hasPrefix("samples=") })
            .flatMap { Int($0.dropFirst("samples=".count)) } ?? 0
        let state = await Self.mainRead {
            ChatScrollBridge.shared.state(
                includeSamples: sampleLimit > 0,
                sampleLimit: sampleLimit > 0 ? min(sampleLimit, 200) : 0
            )
        }
        return jsonResponse(state)
    }

    /// POST /api/scroll — drive the chat scroll. Body:
    ///   { "action": "scrollBy" | "toTop" | "toBottom" | "toAnchor" | "wheel",
    ///     "pixels": 240,            // scrollBy: px (positive down)
    ///     "direction": "up"|"down", // wheel only
    ///     "times": 40,              // wheel only
    ///     "intervalMs": 16,         // wheel only
    ///     "anchor": "<messageId>" } // toAnchor only
    func handleScroll(body: String, query: String = "") async -> String {
        let data = body.data(using: .utf8)
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let action = json?["action"] as? String ?? ""
        let receivedAt = Date()
        let result = await Self.mainRead { () -> [String: Any] in
            let taskStartedAt = Date()
            var result: [String: Any] = [:]
            result["diag"] = [
                "waitMs": (taskStartedAt.timeIntervalSince(receivedAt) * 1000).rounded(),
                "workMs": 0
            ]
            guard !action.isEmpty else {
                return ["ok": false, "error": "action is required (scrollBy|toTop|toBottom|toAnchor|wheel)"]
            }
            defer {
                var diag = result["diag"] as? [String: Any] ?? [:]
                diag["workMs"] = ((Date().timeIntervalSince(taskStartedAt)) * 1000).rounded()
                result["diag"] = diag
            }
            switch action {
            case "scrollBy":
                guard let pixels = json?["pixels"] as? Double else {
                    result = ["ok": false, "error": "pixels required (Double)"]
                    return result
                }
                result = ChatScrollBridge.shared.scrollBy(
                    pixels: CGFloat(pixels),
                    source: "api"
                )
            case "toTop":
                result = ChatScrollBridge.shared.scrollToTop(source: "api")
            case "toBottom":
                result = ChatScrollBridge.shared.scrollToBottom(source: "api")
            case "toAnchor":
                guard let anchor = json?["anchor"] as? String, !anchor.isEmpty else {
                    result = ["ok": false, "error": "anchor required (messageId)"]
                    return result
                }
                result = ChatScrollBridge.shared.scroll(toAnchor: anchor)
            case "wheel":
                guard let pixels = json?["pixels"] as? NSNumber else {
                    result = ["ok": false, "error": "pixels required (Int)"]
                    return result
                }
                let direction = json?["direction"] as? String ?? "down"
                let times = (json?["times"] as? Int) ?? 20
                let intervalMs = (json?["intervalMs"] as? Int) ?? 16
                result = ChatScrollBridge.shared.postWheel(
                    pixels: pixels.int32Value,
                    times: times,
                    intervalMilliseconds: intervalMs,
                    direction: direction
                )
            case "debugHit":
                result = ChatScrollBridge.shared.hitChain()
            default:
                result = ["ok": false, "error": "unknown action \(action)"]
            }
            return result
        }
        return jsonResponse(result)
    }
}
