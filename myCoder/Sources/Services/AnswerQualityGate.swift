import Foundation

/// The standing per-session order «не останавливайся, пока план не выполнен».
///
/// In-memory by design: a restart clears it, and the user re-issues the
/// order with their next message. A persisted eternal auto-continue that
/// survives restarts would be a foot-gun, not a feature.
enum NoStopOrderStore {
    private static let lock = NSLock()
    private static var orders: Set<String> = []

    static func setOrdered(sessionID: String) {
        lock.lock(); defer { lock.unlock() }
        orders.insert(sessionID)
    }

    static func isOrdered(sessionID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return orders.contains(sessionID)
    }

    static func clear(sessionID: String) {
        lock.lock(); defer { lock.unlock() }
        orders.remove(sessionID)
    }
}

/// The internal model's devil's-advocate verdict on the big model's answer.
struct QualityGateVerdict: Equatable, Sendable {
    let score: Int
    let findings: [String]
    let missing: [String]
    let requiresUser: Bool
    let reason: String
}

enum QualityGateDecision: Equatable {
    case accept(reason: String)
    case continueTurn(feedback: String)
    case askUser(reason: String)
}

/// Owner design (2026-11-04): after the big model's full answer the internal
/// model re-reviews the work as a devil's advocate. Below the threshold with
/// an unfinished plan and a standing «don't stop» order, the analysis is sent
/// back into the model automatically. The loop stops only when the user's
/// help is critically required or the depth cap is hit.
///
/// Architecture as everywhere in the pipeline: the host owns the facts
/// (plan items, order detection, parsing), the internal model only judges —
/// a verdict that cannot be parsed is a skip, never an invented score.
enum AnswerQualityGate {

    static let qualityThreshold = 95
    /// Auto-continues per user turn. Every continuation runs the gate again;
    /// the cap turns a stubborn model into a bounded, honest sequence.
    static let maxAutoContinues = 3

    // MARK: - Standing order

    /// Deterministic cue matching over the user's own words. Cues are long
    /// enough that ordinary mentions of "стоп" in a request do not arm the
    /// loop ("останови движок" does not match any cue).
    static func userOrderedNoStop(in text: String) -> Bool {
        let lower = text.lowercased()
        let cues = [
            "не останавливайся", "не останавливаться", "не останавливай",
            "не сбрасывай пока", "не останавливай работу",
            "продолжай без остановок", "продолжай без пауз",
            "пока план не выполн", "пока весь план не выполн",
            "пока не выполнишь весь план", "пока не выполнен весь план",
            "пока всё не будет сделано",
            "don't stop until", "do not stop until",
            "keep going until the plan"
        ]
        return cues.contains { lower.contains($0) }
    }

    // MARK: - Plan state

    /// A plan is complete when nothing is open. `failed`/`blocked` are open:
    /// they demand work, they are not a reason to keep waiting quietly.
    static func planIsComplete(items: [PlanTodoItem]) -> Bool {
        items.allSatisfy { item in
            ["done", "completed", "skipped"].contains(item.status.lowercased())
        }
    }

    // MARK: - Reviewer prompt

    static func verdictPrompt(request: String, answer: String, planText: String) -> [DirectChatMessage] {
        let system = """
        Ты строгий внутренний ревьюер (адвокат дьявола) приложения myCoder. \
        Ты оцениваешь качество выполнения задачи большой языковой моделью. \
        Безжалостен к пустым обещаниям: «сделал бы», «стоит добавить» и пересказ плана \
        вместо реальной работы не считаются выполнением. Отвечай ТОЛЬКО JSON, \
        без markdown-обёртки и без текста вокруг:
        {"score": <0-100>, "findings": ["что реально сделано"], "missing": ["что не сделано или сделано плохо"], "requiresUser": <true|false>, "reason": "краткое обоснование"}
        Правила:
        - score ≥ 95 только если каждый пункт плана закрыт реальной работой.
        - requiresUser = true только когда вмешательство пользователя критически \
        необходимо (нет доступов/креденшелов, опасное действие, внешняя блокировка). \
        Простая незакрытая работа требуетUser = false.
        """
        let user = """
        ЗАДАЧА ПОЛЬЗОВАТЕЛЯ:
        \(request)

        ПЛАН (текущие статусы):
        \(planText.isEmpty ? "(открытых пунктов нет в тексте)" : planText)

        ОТВЕТ МОДЕЛИ:
        \(answer)

        Оцени качество выполнения. Только JSON.
        """
        return [
            DirectChatMessage(role: "system", content: system),
            DirectChatMessage(role: "user", content: user)
        ]
    }

    // MARK: - Verdict parsing

    /// Extracts the first balanced JSON object and decodes it tolerantly.
    /// Anything undecodable is nil: the gate never invents a score.
    static func parseVerdict(from text: String) -> QualityGateVerdict? {
        guard let data = firstJSONData(in: text) else { return nil }
        struct DTO: Decodable {
            let score: Int?
            let findings: [String]?
            let missing: [String]?
            let requiresUser: Bool?
            let reason: String?
        }
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else { return nil }
        let score = min(max(dto.score ?? 0, 0), 100)
        return QualityGateVerdict(
            score: score,
            findings: (dto.findings ?? []).filter { !$0.isEmpty },
            missing: (dto.missing ?? []).filter { !$0.isEmpty },
            requiresUser: dto.requiresUser ?? false,
            reason: dto.reason ?? ""
        )
    }

    /// Byte-accurate balanced scan: tracks brace depth and string state so a
    /// JSON body containing braces in quotes does not truncate early.
    private static func firstJSONData(in text: String) -> Data? {
        let bytes = Array(text.utf8)
        guard let start = bytes.firstIndex(of: UInt8(ascii: "{")) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in start..<bytes.count {
            let byte = bytes[index]
            if escaped {
                escaped = false
                continue
            }
            if inString {
                if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 {
                    return Data(bytes[start...index])
                }
            }
        }
        return nil
    }

    // MARK: - Decision

    static func decision(verdict: QualityGateVerdict,
                         planComplete: Bool,
                         noStopOrdered: Bool) -> QualityGateDecision {
        if verdict.requiresUser {
            return .askUser(reason: verdict.reason.isEmpty
                ? "внутренний ревьюер требует вмешательства пользователя"
                : "внутренний ревьюер требует вмешательства пользователя: \(verdict.reason)")
        }
        if planComplete {
            return .accept(reason: "план выполнен — оценка \(verdict.score) зафиксирована")
        }
        if verdict.score >= qualityThreshold {
            return .accept(reason: "оценка \(verdict.score) ≥ \(qualityThreshold)")
        }
        if noStopOrdered {
            return .continueTurn(feedback: continueFeedback(verdict: verdict))
        }
        return .accept(reason: "оценка \(verdict.score) — авто-продолжение не заказано")
    }

    /// The message automatically sent back into the big model: the analysis,
    /// what is missing, and the fact that nobody told it to stop.
    static func continueFeedback(verdict: QualityGateVerdict) -> String {
        var lines: [String] = []
        lines.append("[Авто-продолжение: контроль качества] Оценка выполнения: \(verdict.score)/100 (порог \(qualityThreshold)).")
        if !verdict.findings.isEmpty {
            lines.append("Сделано: " + verdict.findings.joined(separator: "; "))
        }
        if !verdict.missing.isEmpty {
            lines.append("Не сделано или сделано плохо: " + verdict.missing.joined(separator: "; "))
        }
        if !verdict.reason.isEmpty {
            lines.append("Обоснование ревьюера: \(verdict.reason)")
        }
        lines.append("Продолжай работу: команды останавливаться не было — план должен быть выполнен целиком. "
            + "Закрой каждый пункт из «не сделано» реальной работой; отчёт словами без работы не принимается.")
        return lines.joined(separator: "\n")
    }

    /// The chat-visible one-line note about the verdict.
    static func note(for verdict: QualityGateVerdict, decision: QualityGateDecision) -> String {
        var line = "⚖️ Контроль качества (адвокат дьявола): \(verdict.score)/100."
        if !verdict.missing.isEmpty {
            line += " Открыто: " + verdict.missing.prefix(3).joined(separator: "; ") + "."
        }
        switch decision {
        case .accept(let reason):
            line += " Принято: \(reason)."
        case .continueTurn:
            line += " Оценка ниже \(qualityThreshold), план не готов — разбор отправлен модели, работа продолжается."
        case .askUser(let reason):
            line += " Требуется пользователь: \(reason)"
        }
        return line
    }
}

/// Runs the review through the ordered internal-model list and turns the
/// verdict into a decision. The completion is injectable so the pipeline is
/// testable end to end; production uses `InternalModelRunner.complete`.
enum AnswerQualityGateRunner {

    struct Outcome: Equatable {
        let decision: QualityGateDecision
        /// nil means the gate was skipped honestly (no model, unparsable
        /// answer, or nothing to demand) — never an invented score.
        let verdict: QualityGateVerdict?
    }

    static func evaluate(request: String,
                         answer: String,
                         planItems: [PlanTodoItem],
                         noStopOrdered: Bool,
                         complete: ([DirectChatMessage]) async throws -> String = { messages in
                             try await InternalModelRunner.complete(messages: messages)
                         }) async -> Outcome {
        // A finished plan has nothing to demand: no model call is spent.
        guard !AnswerQualityGate.planIsComplete(items: planItems) else {
            return Outcome(decision: .accept(reason: "план выполнен — гейт не требуется"), verdict: nil)
        }
        let planText = planItems.map(PlanTodoBridge.planLine(for:)).joined(separator: "\n")
        let raw: String
        do {
            raw = try await complete(
                AnswerQualityGate.verdictPrompt(request: request, answer: answer, planText: planText)
            )
        } catch {
            return Outcome(decision: .accept(
                reason: "внутренняя модель недоступна (\(error.localizedDescription)) — гейт пропущен"),
                verdict: nil)
        }
        guard let verdict = AnswerQualityGate.parseVerdict(from: raw) else {
            return Outcome(decision: .accept(
                reason: "ответ внутренней модели не разобран — гейт пропущен"),
                verdict: nil)
        }
        // The guard above proved the plan is open; the decision's
        // `planComplete` input is therefore false here.
        return Outcome(
            decision: AnswerQualityGate.decision(
                verdict: verdict,
                planComplete: false,
                noStopOrdered: noStopOrdered
            ),
            verdict: verdict
        )
    }
}
