import Foundation

// MARK: - Routes and transport

/// Routes the spec planner can talk to directly. Chat-only transports (web,
/// ACP, the MiMo serve session API) are deliberately not listed: the wizard
/// must not create visible chat sessions for its internal turns.
enum SpecPlannerRoute: Equatable {
    case openAICompatible(baseURL: String, apiKey: String?, model: String)
    case openCodeServe(baseURL: String, headers: [String: String], providerID: String, model: String)
    case autoFree(model: String)

    init?(sendRoute: SendRoute, model: String) {
        switch sendRoute {
        case .openAICompatible(let baseURL, let apiKey, let routeModel):
            self = .openAICompatible(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model.isEmpty ? routeModel : model
            )
        case .openCodeServe(let baseURL, let headers, let providerID, let routeModel):
            self = .openCodeServe(
                baseURL: baseURL,
                headers: headers,
                providerID: providerID,
                model: model.isEmpty ? routeModel : model
            )
        case .autoFree:
            self = .autoFree(model: model)
        case .mimoServe, .acp, .web, .none:
            return nil
        }
    }
}

struct SpecCompletionRequest: Equatable {
    let route: SpecPlannerRoute
    let messages: [DirectChatMessage]
}

protocol SpecCompletionProviding {
    func complete(_ request: SpecCompletionRequest) async throws -> String
}

struct LiveSpecCompletionProvider: SpecCompletionProviding {
    /// Local planner models regularly need more than the two-minute chat
    /// default once the interview grows. The planner is a background call,
    /// so a longer window is safe and avoids losing a turn to a timeout.
    let timeout: TimeInterval

    init(timeout: TimeInterval = 600) {
        self.timeout = timeout
    }

    func complete(_ request: SpecCompletionRequest) async throws -> String {
        switch request.route {
        case .openAICompatible(let baseURL, let apiKey, let model):
            let result = try await DirectChatClient.send(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                messages: request.messages,
                transport: URLSessionDirectChatTransport(timeout: timeout)
            )
            return result.content

        case .openCodeServe(let baseURL, let headers, let providerID, let model):
            let text = request.messages
                .map { "\($0.role): \($0.content)" }
                .joined(separator: "\n\n")
            let result = try await OpenCodeServeClient.send(
                baseURL: baseURL,
                headers: headers,
                modelID: model,
                text: text,
                providerID: providerID,
                transport: URLSessionDirectChatTransport(timeout: timeout)
            )
            return result.content

        case .autoFree(let model):
            let messages = request.messages.map {
                MyCoderAutoFreeClient.Message(role: $0.role, content: $0.content)
            }
            var text = ""
            for try await event in MyCoderAutoFreeClient.shared.chatCompletion(
                model: model,
                messages: messages
            ) {
                if case .content(let chunk) = event {
                    text += chunk
                }
            }
            return text
        }
    }
}

// MARK: - Service

struct SpecPlannerTurn: Equatable {
    let role: String
    let content: String
}

enum SpecPlannerServiceError: Error, Equatable, LocalizedError {
    case emptyResponse
    case emptySpecification
    case unsupportedRoute

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "The model returned an empty response"
        case .emptySpecification:
            return "The model returned an empty specification"
        case .unsupportedRoute:
            return "The selected provider cannot create the plan. Choose an OpenAI-compatible, local or free model."
        }
    }
}

struct SpecPlannerService {
    let provider: SpecCompletionProviding

    init(provider: SpecCompletionProviding = LiveSpecCompletionProvider()) {
        self.provider = provider
    }

    func nextInterviewQuestion(projectName: String,
                               brief: SpecWizardDraft,
                               turns: [SpecPlannerTurn],
                               route: SpecPlannerRoute,
                               language: AppLanguage = .english,
                               requireMoreQuestions: Bool = false) async throws -> SpecInterviewQuestion {
        let raw = try await complete(
            route: route,
            messages: SpecPlannerPrompts.interviewMessages(
                projectName: projectName,
                brief: brief,
                turns: turns,
                language: language,
                requireMoreQuestions: requireMoreQuestions
            )
        )
        return try SpecInterviewLogic.decode(raw)
    }

    func generateSpecification(projectName: String,
                               brief: SpecWizardDraft,
                               turns: [SpecPlannerTurn],
                               route: SpecPlannerRoute,
                               repositoryContext: String = "",
                               language: AppLanguage = .english) async throws -> String {
        let raw = try await complete(
            route: route,
            messages: SpecPlannerPrompts.specificationMessages(
                projectName: projectName,
                brief: brief,
                turns: turns,
                repositoryContext: repositoryContext,
                language: language
            )
        )
        let spec = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpecRevisionLogic.isValid(content: spec) else {
            throw SpecPlannerServiceError.emptySpecification
        }
        return spec
    }

    func generateDecomposition(projectName: String,
                               brief: SpecWizardDraft,
                               specification: String,
                               route: SpecPlannerRoute,
                               repositoryContext: String = "",
                               language: AppLanguage = .english) async throws -> SpecDecomposition {
        let raw = try await complete(
            route: route,
            messages: SpecPlannerPrompts.decompositionMessages(
                projectName: projectName,
                brief: brief,
                specification: specification,
                repositoryContext: repositoryContext,
                language: language
            )
        )
        return try SpecDecompositionLogic.decode(raw)
    }

    private func complete(route: SpecPlannerRoute,
                          messages: [DirectChatMessage]) async throws -> String {
        let raw = try await provider.complete(
            SpecCompletionRequest(route: route, messages: messages)
        )
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpecPlannerServiceError.emptyResponse
        }
        return raw
    }
}

// MARK: - Prompts

enum SpecPlannerPrompts {
    static func interviewMessages(projectName: String,
                                  brief: SpecWizardDraft,
                                  turns: [SpecPlannerTurn],
                                  language: AppLanguage = .english,
                                  requireMoreQuestions: Bool = false) -> [DirectChatMessage] {
        var system = """
        You are the specification planner for a software project.
        Ask exactly ONE question at a time to remove ambiguity from the brief.
        Ask ONLY what you cannot infer from the brief and the previous answers:
        never repeat a question, never ask what the user already answered, and
        never ask a generic question whose answer cannot change the project.
        Track your own uncertainty: `uncertainty` is a number from 0 to 1 that
        says how much of the task is still unclear (0 = fully understood).
        Keep asking while uncertainty > \(SpecInterviewLogic.uncertaintyThreshold).
        Prefer concrete, answerable questions. Do not write code and do not invent requirements.
        \(languageRule(language))

        Return ONLY a JSON object, with no prose around it:
        {"id":"short_stable_id","question":"...","suggested_answers":["..."],"uncertainty":0.4,"done":false}
        suggested_answers must contain 1-5 short options, or be empty.
        As soon as uncertainty is \(SpecInterviewLogic.uncertaintyThreshold) or lower, stop asking and return:
        {"id":"final","done":true,"uncertainty":0.05,"summary":"what exactly must be built, in 2-4 sentences"}
        The summary must restate what you understood: the goal, the stack, the
        concrete behaviour and the constraints — short, no new requirements.
        """
        if requireMoreQuestions {
            system += """


            Your previous answer was done:true while uncertainty was still above
            \(SpecInterviewLogic.uncertaintyThreshold) — the task is not clear enough yet.
            Ask the next single question that removes the most remaining ambiguity.
            """
        }
        return [
            DirectChatMessage(role: "system", content: system),
            DirectChatMessage(role: "user", content: interviewUserText(
                projectName: projectName,
                brief: brief,
                turns: turns
            ))
        ]
    }

    static func specificationMessages(projectName: String,
                                      brief: SpecWizardDraft,
                                      turns: [SpecPlannerTurn],
                                      repositoryContext: String = "",
                                      language: AppLanguage = .english) -> [DirectChatMessage] {
        let system = """
        You write a precise, testable technical specification in Markdown.
        Use only the brief and the interview answers. Include: goal, scope, non-goals,
        functional requirements, constraints and acceptance criteria.
        When repository context is present, stay consistent with the existing stack and
        structure, but never invent requirements from it.
        Do not write implementation code and do not add requirements that were not discussed.
        \(languageRule(language))
        Return the Markdown document only.
        """
        return [
            DirectChatMessage(role: "system", content: system),
            DirectChatMessage(role: "user", content: interviewUserText(
                projectName: projectName,
                brief: brief,
                turns: turns,
                repositoryContext: repositoryContext
            ))
        ]
    }

    static func decompositionMessages(projectName: String,
                                      brief: SpecWizardDraft,
                                      specification: String,
                                      repositoryContext: String = "",
                                      language: AppLanguage = .english) -> [DirectChatMessage] {
        let system = """
        Split the specification into atomic implementation nodes. Every node must be
        independently verifiable and small enough for one focused coding session.
        Use stable keys (N1, N2, ...), explicit dependencies and concrete acceptance criteria.
        The dependency graph must be acyclic.
        \(languageRule(language))
        Return ONLY JSON:
        {"nodes":[{"key":"N1","title":"...","description":"...","kind":"task",
        "acceptance_criteria":["..."],"depends_on":[]}]}
        Do not add prose or Markdown fences. Keep keys and kind values in English.
        """
        let user = """
        Project: \(projectName)
        Goal: \(brief.goal)
        Stack: \(brief.stack)
        Constraints: \(brief.constraints)

        Specification:
        \(specification)
        \(repositoryContext.isEmpty ? "" : "\n\(repositoryContext)")
        """
        return [
            DirectChatMessage(role: "system", content: system),
            DirectChatMessage(role: "user", content: user)
        ]
    }

    private static func languageRule(_ language: AppLanguage) -> String {
        "Write every human-readable string (questions, suggested answers, summary, specification, node titles, descriptions and acceptance criteria) in \(language.rawValue). Keep JSON keys and kind values exactly as specified."
    }

    private static func interviewUserText(projectName: String,
                                          brief: SpecWizardDraft,
                                          turns: [SpecPlannerTurn],
                                          repositoryContext: String = "") -> String {
        var lines = [
            "Project: \(projectName)",
            "Goal: \(brief.goal)",
            "Stack: \(brief.stack)",
            "Constraints: \(brief.constraints)"
        ]
        if !turns.isEmpty {
            lines.append("")
            lines.append("Interview so far:")
            for turn in turns {
                lines.append("\(turn.role): \(turn.content)")
            }
        }
        if !repositoryContext.isEmpty {
            lines.append("")
            lines.append(repositoryContext)
        }
        return lines.joined(separator: "\n")
    }
}
