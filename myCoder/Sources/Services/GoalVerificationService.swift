import Foundation

/// Runs the automatic post-turn goal verification: after the model's answer is
/// complete, an internal model acts as devil's advocate and checks whether the
/// plan steps are REALLY done. When not complete, a continuation prompt
/// («продолжай по плану, обнови прогресс») is returned so the host can inject
/// it back into the chat.
struct GoalVerificationService {
    typealias Transport = (_ system: String, _ user: String) async throws -> String

    var transport: Transport

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    struct Outcome: Equatable, Sendable {
        var verdict: GoalVerdict
        var continuation: String?
    }

    func verify(goal: UserGoal,
                lastAssistantText: String,
                language: AppLanguage) async -> Outcome {
        let system = GoalVerificationPromptBuilder.devilAdvocateSystem(language: language)
        let user = GoalVerificationPromptBuilder.verificationUser(
            goal: goal, lastAssistantText: lastAssistantText, language: language)

        var modelVerdict: GoalVerdict? = nil
        do {
            let answer = try await transport(system, user)
            modelVerdict = GoalVerdictParser.parse(answer)
        } catch {
            modelVerdict = nil
        }

        let verdict = GoalVerdictParser.merged(model: modelVerdict, plan: goal.plan)
        let continuation: String?
        if verdict.complete {
            continuation = nil
        } else {
            continuation = GoalVerificationPromptBuilder.continuationMessage(
                language: language, reason: verdict.reason)
        }
        return Outcome(verdict: verdict, continuation: continuation)
    }
}
