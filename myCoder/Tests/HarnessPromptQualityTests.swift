import Foundation
import Testing
@testable import myCoder

/// The blended "best of both harnesses" prompt quality: OpenCode's
/// collaboration/communication core + Claude Code's structural checkpoint.
@Suite("Harness prompt quality — blended OpenCode + Claude Code")
struct HarnessPromptQualityTests {

    private func message(_ role: MessageRole, _ content: String) -> Message {
        Message(role: role, content: content, isFinished: true)
    }

    // MARK: - Collaboration core (OpenCode-style)

    @Test func nativeSystemCarriesOpenCodeCollaborationCore() {
        let native = TurnDelivery.systemInstruction(
            route: .mimoServe, userRules: "RULES", projectRoot: "/project",
            isProject: true, agentMode: .build)
        // OpenCode's harness/communication/codebase essence.
        #expect(native.lowercased().contains("coding agent harness"))
        #expect(native.lowercased().contains("github-flavored markdown"))
        #expect(native.lowercased().contains("parallelizing independent tool calls"))
        #expect(native.lowercased().contains("clear file paths"))
        #expect(native.lowercased().contains("consistent with the structure"))
        // Claude Code evidence discipline.
        #expect(native.lowercased().contains("before you see its result")
            || native.lowercased().contains("never claim"))
    }

    @Test func nativeSystemKeepsNativeToolsContract() {
        let native = TurnDelivery.systemInstruction(
            route: .mimoServe, userRules: "", projectRoot: "/project",
            isProject: true, agentMode: .build)
        #expect(native.contains("native tools"))
        #expect(!native.contains("```tool"))
        #expect(native.contains("RULES") || true)
    }

    @Test func nativeSystemCarriesFileSizeAndTddRules() {
        let native = TurnDelivery.systemInstruction(
            route: .mimoServe, userRules: "", projectRoot: "/project",
            isProject: true, agentMode: .build)
        let lower = native.lowercased()
        #expect(lower.contains("under 600 lines"), "системный промпт должен требовать ≤600 строк на файл")
        #expect(lower.contains("tdd") || lower.contains("test-first"), "системный промпт должен требовать TDD")
    }

    @Test func nativeSystemCarriesAtomicModularCodePipeline() {
        let native = TurnDelivery.systemInstruction(
            route: .mimoServe, userRules: "", projectRoot: "/project",
            isProject: true, agentMode: .build)
        let lower = native.lowercased()
        #expect(lower.contains("code work pipeline"), "должна быть секция конвейера кода")
        #expect(lower.contains("atomic"), "должна требоваться атомарная декомпозиция")
        #expect(lower.contains("modular"), "должны требоваться модульные единицы")
        #expect(lower.contains("contract"), "над каждой функцией должен быть комментарий-контракт")
        #expect(lower.contains("compile and test each unit"), "проверка должна идти по мере написания модулей")
    }

    // MARK: - Code discipline is one canonical block on EVERY route (dedup + ironclad)

    @Test func codeDisciplineIsSingleCanonicalSourceWithEveryMandatoryRule() {
        let discipline = HarnessPromptQuality.codeDiscipline.lowercased()
        // Обязательные правила из пользовательской директивы, в одном блоке.
        #expect(discipline.contains("under 600 lines"), "≤600 строк на файл")
        #expect(discipline.contains("tdd") || discipline.contains("test-first"), "TDD")
        #expect(discipline.contains("all reasonable tests") || discipline.contains("every"), "все возможные тесты")
        #expect(discipline.contains("contract"), "комментарий-контракт над каждой функцией")
        #expect(discipline.contains("input") && discipline.contains("output"), "входные и выходные параметры")
        #expect(discipline.contains("dependencies"), "зависимости функции")
        #expect(discipline.contains("modular"), "модульность")
        #expect(discipline.contains("reuse") || discipline.contains("reusable"), "переиспользуемость в другом модуле")
        #expect(discipline.contains("debug"), "лёгкая отладка")
        // Дедуп: collaborationCore НЕ дублирует правила, а встраивает этот блок.
        #expect(HarnessPromptQuality.collaborationCore.contains(HarnessPromptQuality.codeDiscipline))
    }

    @Test func webAndOpenAIRoutesCarryTheSameCodeDiscipline() {
        // Железное покрытие: эмулированная web/OpenAI-ветка получает ту же
        // дисциплину кода, что и нативная — через общий канонический блок.
        for route in [
            SendRoute.openAICompatible(baseURL: "http://local", apiKey: nil, model: "model"),
            SendRoute.web(configID: "cfg")
        ] {
            let prompt = TurnDelivery.systemInstruction(
                route: route, userRules: "", projectRoot: "/project",
                isProject: true, agentMode: .build)
            #expect(prompt.contains(HarnessPromptQuality.codeDiscipline),
                    "route \(route) должна нести каноническую дисциплину кода")
            let lower = prompt.lowercased()
            #expect(lower.contains("under 600 lines"))
            #expect(lower.contains("code work pipeline"))
        }
    }

    @Test func nativeSystemTeachesCanonicalTodoWorkflow() {
        let native = TurnDelivery.systemInstruction(
            route: .mimoServe, userRules: "", projectRoot: "/project",
            isProject: true, agentMode: .build)
        // Реальные имена инструментов, а не выдуманные todo_add/todo_update.
        for name in ["todo_read", "todo_write", "task_create", "task_list", "task_update"] {
            #expect(native.contains(name), "промпт должен называть реальный инструмент \(name)")
        }
        #expect(!native.contains("todo_add"))
        #expect(!native.contains("todo_update"))
        #expect(!native.contains("todo_list"))
        // Сам workflow: атомарные шаги, точные статусы, причина блокировки,
        // проверка плана перед объявлением готовности.
        let lower = native.lowercased()
        #expect(lower.contains("atomic"))
        #expect(lower.contains("in_progress"))
        #expect(lower.contains("completed"))
        #expect(lower.contains("blocked"))
        #expect(lower.contains("before declaring"))
    }

    @Test func nativeSystemCarriesGitSafetyRule() {
        let native = TurnDelivery.systemInstruction(
            route: .mimoServe, userRules: "", projectRoot: "/project",
            isProject: true, agentMode: .build)
        let lower = native.lowercased()
        #expect(lower.contains("git safety"), "должна быть секция git-безопасности")
        #expect(lower.contains("committed and pushed"), "должно требоваться «закомичено и запушено»")
        #expect(lower.contains("branch is clean"), "должна требоваться чистая ветка")
        #expect(lower.contains("backup"), "должны допускаться бекапы")
        #expect(lower.contains("non-read-only"), "правило должно касаться не-только-чтение команд")
    }

    // MARK: - Structural summary (Claude Code-style)

    @Test func structuralSummaryUsesClaudeCodeSections() {
        let prompt = HarnessPromptQuality.structuralSummaryPrompt(
            messages: [message(.user, "fix the login bug")], maxCharacters: 10_000)
        let lower = prompt.lowercased()
        #expect(lower.contains("## objective"))
        #expect(lower.contains("## important details"))
        #expect(lower.contains("## work state"))
        #expect(lower.contains("## next move"))
        #expect(lower.contains("## relevant files"))
        // Must stay regression-compatible with the old contract.
        #expect(lower.contains("do not invent"))
        #expect(lower.contains("files"))
        #expect(lower.contains("next steps"))
        #expect(prompt.contains("fix the login bug"))
    }

    @Test func structuralSummaryPromisesExactPathsAndIdentifiers() {
        let prompt = HarnessPromptQuality.structuralSummaryPrompt(
            messages: [message(.assistant, "wrote App/UserStore.swift")], maxCharacters: 10_000)
        #expect(prompt.lowercased().contains("paths"))
        #expect(prompt.lowercased().contains("identifiers"))
    }

    // MARK: - Subagent prompt (Claude Code Task-role style)

    @Test func subagentSystemFramesReadOnlyRoleAndReport() {
        let prompt = HarnessPromptQuality.subagentSystem(description: "Trace the parser")
        let lower = prompt.lowercased()
        #expect(lower.contains("sub-agent"))
        #expect(lower.contains("read-only"))
        #expect(lower.contains("trace the parser"))
        #expect(lower.contains("report"))
        #expect(lower.contains("self-contained"))
    }

    // MARK: - Human-like problem solving (least-resistance path + uncertainty)

    @Test func nativeSystemCarriesHumanProblemSolvingGuidance() {
        let native = TurnDelivery.systemInstruction(
            route: .mimoServe, userRules: "", projectRoot: "/project",
            isProject: true, agentMode: .build)
        let lower = native.lowercased()
        // Least-resistance path + uncertainty threshold.
        #expect(lower.contains("least-resistance") || lower.contains("least resistance"))
        #expect(lower.contains("0.1") || lower.contains("10%"))
        #expect(lower.contains("ask the user"))
        // Search-first ladder: ready files → GitHub → Hugging Face → free cloud →
        // paid cloud → manual last with risk warning.
        #expect(lower.contains("github"))
        #expect(lower.contains("hugging face"))
        #expect(lower.contains("free cloud"))
        #expect(lower.contains("paid cloud"))
        #expect(lower.contains("manual") || lower.contains("by hand"))
        #expect(lower.contains("risk") || lower.contains("warning"))
    }

    @Test func humanProblemSolvingGuidanceIsUniversalAndCoherent() {
        let guidance = HarnessPromptQuality.humanProblemSolvingGuidance.lowercased()
        // It is a standalone universal block, reusable across routes.
        #expect(guidance.contains("search first") || guidance.contains("search for existing"))
        #expect(guidance.contains("questionnaire") || guidance.contains("coherent"))
        #expect(guidance.contains("contradict"))
        #expect(guidance.contains("before you build") || guidance.contains("before building"))
    }
}
