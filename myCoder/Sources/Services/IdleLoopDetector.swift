import Foundation

/// Harness-tax C3 idle-loop killer (KDD 2026: idle steps are the main tax —
/// every one re-sends the whole context; up to 29% of runs end in TIME/HANG).
/// Pure and testable: the driver feeds each parsed tool call; the third
/// consecutive identical call (name + sorted arguments) reports idle so the
/// turn stops honestly instead of spinning.
struct IdleLoopDetector {
    /// Consecutive identical calls that prove a loop (Goose stops at ~0.2-0.3
    /// idle steps; OpenCode burns 2.0-2.2 — we stop at the third repeat).
    static let repeatThreshold = 3
    /// Hard iteration ceiling even when the provider config allows more
    /// (KDD: a 40-turn cap cuts TIME/HANG tails without hurting solves).
    static let hardIterationCap = 40

    private var lastSignature: String?
    private var streak = 0
    /// Repeat observations so far (2nd identical call = 1 idle step).
    private(set) var idleSteps = 0

    static func signature(of call: WebToolCall) -> String {
        let args = call.arguments.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: ";")
        return "\(call.name)|\(args)"
    }

    /// Feed one parsed call. Returns true when the turn must stop now
    /// (the call must NOT execute again).
    mutating func observe(_ call: WebToolCall) -> Bool {
        let sig = Self.signature(of: call)
        if sig == lastSignature {
            streak += 1
            idleSteps += 1
        } else {
            lastSignature = sig
            streak = 1
        }
        return streak >= Self.repeatThreshold
    }
}
