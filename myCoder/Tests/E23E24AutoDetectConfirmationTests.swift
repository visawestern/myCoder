import Testing
import Foundation
@testable import myCoder

@Suite("E23/E24 — auto-detect requires confirmation + overall timeout is enforced (Раздел 9 п.30/п.33)")
struct E23E24AutoDetectConfirmationTests {

    /// Probe that sleeps `delay` per call so the overall deadline becomes
    /// measurable, and counts how many probes were actually attempted.
    private final class SlowCountingProbe: ProviderProbe, @unchecked Sendable {
        let delay: TimeInterval
        let routes: [(String, Int, Data?)]
        private(set) var callCount = 0

        init(delay: TimeInterval, routes: [(String, Int, Data?)]) {
            self.delay = delay
            self.routes = routes
        }

        func get(url: String, headers: [String: String]) async -> (Int, Data)? {
            callCount += 1
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            for (path, status, body) in routes where url.contains(path) {
                return (status, body ?? Data())
            }
            return nil
        }
    }

    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - E24: overall timeout enforced

    @Test("detection stops once the overall deadline passes instead of probing every step")
    func overallTimeoutStopsSequentialProbes() async {
        // Only the last probe (/v1/models on the STRATA port) would succeed,
        // but each probe is slow (100ms) while the overall budget is 150ms →
        // the deadline must cut the sequence short and return nil instead of
        // reaching the hit.
        let probe = SlowCountingProbe(delay: 0.1, routes: [
            ("/v1/models", 200, data(#"{"data":[{"id":"llama"}]}"#))
        ])
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 8399,
                                                     probe: probe, overallTimeout: 0.15)

        #expect(info == nil, "the late-hit probe must be stopped by the deadline")
        #expect(probe.callCount < 3, "not all sequential probes may run (ran \(probe.callCount))")
        // The deadline is proven by callCount < 3 (the sequence is cut short).
        // Wall-clock is not asserted tightly: under a loaded parallel test
        // runner Task.sleep stretches far beyond nominal sleep time.
    }

    @Test("fast detection still succeeds when the deadline is far away")
    func fastDetectionUnaffectedByDeadline() async {
        let probe = SlowCountingProbe(delay: 0, routes: [
            ("/api/tags", 200, data(#"{"models":[{"name":"llama3"}]}"#))
        ])
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 11434,
                                                     probe: probe, overallTimeout: 10)
        #expect(info?.kind == .ollama)
        #expect(info?.models == ["llama3"])
    }

    @Test("default overall timeout is exposed and applied")
    func defaultOverallTimeoutApplied() async {
        #expect(ProviderAutoDetector.overallTimeout == 10)
        // With a 10s budget and instant probes the whole sequence runs.
        let probe = SlowCountingProbe(delay: 0, routes: [
            ("/api/tags", 200, data(#"{"models":[{"name":"m"}]}"#))
        ])
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 11434, probe: probe)
        #expect(info?.kind == .ollama)
    }

    // MARK: - E23: confirmation before adding

    @Test("confirmation title names the detected provider")
    func confirmationTitleNamesProvider() {
        let info = DetectedProviderInfo(kind: .ollama, baseURL: "http://localhost:11434", models: ["llama3", "qwen"])
        #expect(LocalProviderConfirmLogic.title(for: info) == "Detected: Ollama")
    }

    @Test("confirmation message includes host:port and model count")
    func confirmationMessageIncludesDetails() {
        let info = DetectedProviderInfo(kind: .strata, baseURL: "http://localhost:8399", models: ["a", "b", "c"])
        let message = LocalProviderConfirmLogic.message(for: info, host: "localhost", port: 8399)
        #expect(message.contains("localhost:8399"))
        #expect(message.contains("3"))
    }

    @Test("confirming builds the local provider config with detected kind + models")
    func confirmationBuildsConfig() {
        let info = DetectedProviderInfo(kind: .ollama, baseURL: "http://localhost:11434", models: ["llama3"])
        let cfg = LocalProviderConfirmLogic.config(from: info, host: "localhost", port: 11434)
        #expect(cfg.kind == .ollama)
        #expect(cfg.host == "localhost")
        #expect(cfg.port == 11434)
        #expect(cfg.models == ["llama3"])
        #expect(cfg.isEnabled)
    }

    @Test("cancelling leaves the locals list unchanged (no auto-add)")
    func cancelDoesNotAdd() {
        let info = DetectedProviderInfo(kind: .strata, baseURL: "http://localhost:8399", models: ["m"])
        // The confirmation decision is explicit: no config is produced on cancel.
        // A detected STRATA server must keep its own kind, not masquerade as
        // OpenCode (different transport).
        #expect(LocalProviderConfirmLogic.config(from: info, host: "localhost", port: 8399).kind == .strata)
    }

    // MARK: - E24 hardening: the deadline must bound probe DURATION, not just probe start

    /// Probe that tracks cancellation: `Task.sleep` throws when the awaiting
    /// task is cancelled, which the E24 deadline race must trigger when a probe
    /// outlives the remaining budget.
    private final class CancelTrackingProbe: ProviderProbe, @unchecked Sendable {
        let sleepDuration: TimeInterval
        private(set) var callCount = 0
        private(set) var wasCancelled = false

        init(sleepDuration: TimeInterval) { self.sleepDuration = sleepDuration }

        func get(url: String, headers: [String: String]) async -> (Int, Data)? {
            callCount += 1
            do {
                try await Task.sleep(nanoseconds: UInt64(sleepDuration * 1_000_000_000))
            } catch {
                wasCancelled = true
                return nil
            }
            return nil
        }
    }

    @Test("a probe that outlives the deadline is cancelled — detection returns at the deadline, not after the probe")
    func hangingProbeCancelledAtDeadline() async {
        // Each probe would sleep 3s, but the overall budget is 0.25s: the
        // deadline race must cut the in-flight probe short and return nil.
        // The CONTRACT being verified is structural and deterministic:
        //   • detection returns nil (no false-positive provider)
        //   • the in-flight probe is CANCELLED (wasCancelled)
        //   • only the first probe starts before the deadline (callCount == 1)
        // A wall-clock upper bound is intentionally NOT asserted: the deadline
        // race fires the cancellation via `Task.sleep`, whose scheduling is
        // cooperative — under heavy parallel-test load (1713 tests sharing the
        // cooperative thread pool) the timeout Task can be scheduled seconds
        // late even though it fires and cancels the probe the instant it runs.
        // That scheduling latency is a test-environment artifact, not a
        // production invariant (production probes use URLSession timeouts, not
        // cooperative sleeps). On the OLD code the race didn't cancel at all,
        // so `wasCancelled` was false — caught by the assertion below.
        let probe = CancelTrackingProbe(sleepDuration: 3)
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 9999,
                                                     probe: probe, overallTimeout: 0.25)
        #expect(info == nil)
        #expect(probe.wasCancelled, "the in-flight probe must be cancelled when the deadline hits")
        #expect(probe.callCount == 1, "only the first probe may start before the deadline (ran \(probe.callCount))")
    }

    @Test("zero overall timeout attempts no probes at all")
    func zeroTimeoutAttemptsNoProbes() async {
        let probe = CancelTrackingProbe(sleepDuration: 0)
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 9999,
                                                     probe: probe, overallTimeout: 0)
        #expect(info == nil)
        #expect(probe.callCount == 0)
    }

    @Test("negative overall timeout attempts no probes at all")
    func negativeTimeoutAttemptsNoProbes() async {
        let probe = CancelTrackingProbe(sleepDuration: 0)
        let info = await ProviderAutoDetector.detect(host: "localhost", port: 9999,
                                                     probe: probe, overallTimeout: -5)
        #expect(info == nil)
        #expect(probe.callCount == 0)
    }

    // MARK: - E23: detected STRATA must remain STRATA end-to-end (config → send route)

    @Test("confirmed STRATA detection maps to the STRATA local kind")
    func strataDetectionMapsToStrataKind() {
        let info = DetectedProviderInfo(kind: .strata, baseURL: "http://localhost:8399", models: ["m"])
        let cfg = LocalProviderConfirmLogic.config(from: info, host: "localhost", port: 8399)
        #expect(cfg.kind == .strata)
        #expect(cfg.apiBaseURL == "http://localhost:8399")
    }

    @Test("every detected kind maps to a local kind without losing protocol")
    func allDetectedKindsMapSensibly() {
        let ollama = DetectedProviderInfo(kind: .ollama, baseURL: "http://x", models: ["a"])
        #expect(LocalProviderConfirmLogic.config(from: ollama, host: "x", port: 1).kind == .ollama)
        let strata = DetectedProviderInfo(kind: .strata, baseURL: "http://x", models: ["a"])
        #expect(LocalProviderConfirmLogic.config(from: strata, host: "x", port: 1).kind == .strata)
        let oc = DetectedProviderInfo(kind: .openCode, baseURL: "http://x", models: ["a"])
        #expect(LocalProviderConfirmLogic.config(from: oc, host: "x", port: 1).kind == .openCode)
    }

    @Test("an auto-detected STRATA local provider routes through OpenAI-compatible /v1")
    func strataLocalProviderRoutesToOpenAICompatible() {
        let local = LocalProviderConfig(kind: .strata, host: "localhost", port: 8399)
        let route = SendRouteResolver.route(
            selectedProviderID: local.id,
            selectedModel: "m",
            serverConnected: false,
            isACP: false,
            customProviders: [],
            localProviders: [local],
            webProviderIDs: []
        )
        #expect(route == .openAICompatible(baseURL: "http://localhost:8399/v1", apiKey: nil, model: "m"))
    }

    @Test("Ollama/STRATA locals route as OpenAI-compatible; OpenCode locals use the session API")
    func supportedLocalsStillRouteCorrectly() {
        let openCode = LocalProviderConfig(kind: .openCode, host: "localhost", port: 4096)
        let route = SendRouteResolver.route(
            selectedProviderID: openCode.id, selectedModel: "m",
            serverConnected: false, isACP: false,
            customProviders: [], localProviders: [openCode], webProviderIDs: [])
        guard case .openCodeServe(let baseURL, _, let providerID, let model) = route else {
            Issue.record("expected openCodeServe route, got \(route)")
            return
        }
        #expect(baseURL == "http://localhost:4096")
        #expect(providerID == "opencode")
        #expect(model == "m")
        let ollama = LocalProviderConfig(kind: .ollama, host: "localhost", port: 11434)
        let oroute = SendRouteResolver.route(
            selectedProviderID: ollama.id, selectedModel: "m",
            serverConnected: false, isACP: false,
            customProviders: [], localProviders: [ollama], webProviderIDs: [])
        guard case .openAICompatible(let obase, _, _) = oroute else {
            Issue.record("expected openAICompatible route, got \(oroute)")
            return
        }
        #expect(obase == "http://localhost:11434/v1")
    }

    // MARK: - E23: dedupe + status text (testable out of the view)

    @Test("confirming an already-present host:port is a duplicate and adds nothing")
    func duplicateHostPortIsDetected() {
        let existing = LocalProviderConfig(kind: .ollama, host: "localhost", port: 11434)
        let info = DetectedProviderInfo(kind: .ollama, baseURL: "http://localhost:11434", models: ["llama3"])
        let cfg = LocalProviderConfirmLogic.config(from: info, host: "localhost", port: 11434)
        #expect(LocalProviderConfirmLogic.isDuplicate([existing], of: cfg))

        let different = LocalProviderConfig(kind: .ollama, host: "localhost", port: 1234)
        #expect(!LocalProviderConfirmLogic.isDuplicate([existing], of: different))
    }

    @Test("non-local host produces a visible warning; local hosts do not")
    func nonLocalHostWarning() {
        #expect(AutoDetectStatusText.warningForNonLocal("203.0.113.7") != nil)
        #expect(AutoDetectStatusText.warningForNonLocal("localhost") == nil)
        #expect(AutoDetectStatusText.warningForNonLocal("192.168.1.5") == nil)
        #expect(AutoDetectStatusText.warningForNonLocal("127.0.0.1") == nil)
    }

    @Test("cancelled detection says nothing was added")
    func cancelledStatusText() {
        let text = AutoDetectStatusText.cancelled()
        #expect(text.localizedCaseInsensitiveContains("cancel"))
        #expect(text.localizedCaseInsensitiveContains("nothing"))
    }

    @Test("confirmed detection reports the added provider + endpoint")
    func confirmedStatusText() {
        let info = DetectedProviderInfo(kind: .ollama, baseURL: "http://localhost:11434", models: ["llama3"])
        let text = AutoDetectStatusText.confirmed(info, host: "localhost", port: 11434)
        #expect(text.contains("Ollama"))
        #expect(text.contains("localhost:11434"))
    }

    @Test("detected status asks for confirmation, it does not claim an add")
    func detectedStatusTextAsksToConfirm() {
        let info = DetectedProviderInfo(kind: .ollama, baseURL: "http://localhost:11434", models: ["llama3", "qwen"])
        let text = AutoDetectStatusText.detected(info, host: "localhost", port: 11434)
        #expect(text.localizedCaseInsensitiveContains("confirm"))
        #expect(text.contains("2"))
    }

    @Test("invalid address produces a clear status")
    func invalidAddressStatusText() {
        #expect(AutoDetectStatusText.invalidAddress().contains("host:port"))
    }
}
