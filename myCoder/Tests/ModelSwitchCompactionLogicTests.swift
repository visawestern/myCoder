import Testing
import Foundation
@testable import myCoder

/// User directive 2026-11-08: when the user switches to a model whose
/// context window is smaller than the chat's current context, the chat must
/// be compacted before it continues — and the user must be able to stop that
/// compaction, roll it back, or pick another model with a larger window.
@MainActor
@Suite("Сжатие контекста при смене модели")
struct ModelSwitchCompactionLogicTests {

    @Test("Контекст больше окна новой модели — сжатие обязательно")
    func overflowRequiresCompaction() {
        let decision = ModelSwitchCompactionLogic.decision(usedTokens: 120_000, limitTokens: 64_000)
        #expect(decision.required)
        #expect(decision.overflowTokens == 56_000)
        #expect(decision.usedTokens == 120_000)
        #expect(decision.limitTokens == 64_000)
    }

    @Test("Ровно в окно — сжатие не нужно")
    func exactFitDoesNotCompact() {
        let decision = ModelSwitchCompactionLogic.decision(usedTokens: 64_000, limitTokens: 64_000)
        #expect(!decision.required)
        #expect(decision.overflowTokens == 0)
    }

    @Test("Неизвестное окно модели не превращается в принудительное сжатие")
    func unknownWindowDoesNotCompact() {
        let decision = ModelSwitchCompactionLogic.decision(usedTokens: 500_000, limitTokens: 0)
        #expect(!decision.required)
        #expect(decision.overflowTokens == 0)
    }

    @Test("Пустой чат не требует сжатия")
    func emptyChatDoesNotCompact() {
        let decision = ModelSwitchCompactionLogic.decision(usedTokens: 0, limitTokens: 8_000)
        #expect(!decision.required)
    }

    @Test("Модели с окном поменьше текущего контекста не подходят")
    func onlyModelsThatFitAreOffered() {
        let candidates = [
            ModelSwitchCompactionLogic.Candidate(id: "small:8k", window: 8_192, providerID: "p1", providerName: "One"),
            ModelSwitchCompactionLogic.Candidate(id: "fits:128k", window: 131_072, providerID: "p1", providerName: "One"),
            ModelSwitchCompactionLogic.Candidate(id: "fits:256k", window: 262_144, providerID: "p2", providerName: "Two"),
            ModelSwitchCompactionLogic.Candidate(id: "unknown", window: 0, providerID: "p2", providerName: "Two")
        ]
        let fits = ModelSwitchCompactionLogic.modelsThatFit(
            usedTokens: 120_000,
            candidates: candidates
        )
        #expect(fits.map(\.id) == ["fits:256k", "fits:128k"])
        // The provider travels with the model: the escape hatch may live in
        // another provider entirely.
        #expect(fits.map(\.providerID) == ["p2", "p1"])
        #expect(fits.map(\.providerName) == ["Two", "One"])
    }

    @Test("Список подходящих моделей пуст, если никто не вмещает контекст")
    func noModelFits() {
        let fits = ModelSwitchCompactionLogic.modelsThatFit(
            usedTokens: 900_000,
            candidates: [
                ModelSwitchCompactionLogic.Candidate(id: "small", window: 8_192, providerID: "p1", providerName: "One")
            ]
        )
        #expect(fits.isEmpty)
    }

    @Test("Кандидаты собираются из всех провайдеров сразу")
    func candidatesAreBuiltFromEveryProvider() {
        let catalogs = [
            ModelSwitchCompactionLogic.ProviderModels(
                providerID: "p1",
                providerName: "One",
                models: [.init(id: "m1", window: 500_000)]
            ),
            ModelSwitchCompactionLogic.ProviderModels(
                providerID: "p2",
                providerName: "Two",
                models: [
                    .init(id: "m2", window: 1_000_000),
                    .init(id: "m3", window: 0)
                ]
            )
        ]
        let candidates = ModelSwitchCompactionLogic.candidates(from: catalogs)
        #expect(candidates.map(\.id) == ["m1", "m2", "m3"])
        #expect(candidates.map(\.providerID) == ["p1", "p2", "p2"])
        #expect(candidates.map(\.providerName) == ["One", "Two", "Two"])
        // The same model id in two providers is two different choices.
        #expect(Set(candidates.map(\.key)).count == candidates.count)
    }

    @Test("Отменённое сжатие не возвращает сводку")
    func cancelledSummarizationThrows() async {
        let summarizer = ConversationSummarizer(transport: { _ in
            try? await Task.sleep(nanoseconds: 200_000_000)
            return "- summary"
        })
        let messages = (0..<4).map { index in
            Message(role: index % 2 == 0 ? .user : .assistant, content: "turn \(index)", isFinished: true)
        }
        let task = Task { try await summarizer.summarize(messages: messages) }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("Отмена во время запроса даёт отмену, а не ошибку транспорта")
    func cancellationWinsOverTransportError() async {
        let summarizer = ConversationSummarizer(transport: { _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            throw DirectChatError.transport("connection closed")
        })
        let messages = (0..<4).map { index in
            Message(role: index % 2 == 0 ? .user : .assistant, content: "turn \(index)", isFinished: true)
        }
        let task = Task { try await summarizer.summarize(messages: messages) }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("Откат возвращает модели полную историю")
    func rollbackRestoresModelHistory() {
        let store = MessageStore()
        let turns = (0..<6).map { index in
            Message(role: index % 2 == 0 ? .user : .assistant, content: "turn \(index)", isFinished: true)
        }
        turns.forEach { store.append($0) }
        let original = ConversationCompactionLogic.historyForModel(store.messages)

        let summary = ConversationCompactionLogic.summaryMessage(summary: "- summary")
        store.append(summary)
        let note = Message(role: .assistant, content: "Context compacted", isFinished: true)
        store.append(note)

        // The model now sees the summary and the note — not the old turns.
        #expect(ConversationCompactionLogic.historyForModel(store.messages).count == 2)

        for target in ModelSwitchCompactionLogic.rollbackTargets(
            summaryMessageID: summary.id,
            noticeMessageID: note.id
        ) {
            store.remove(id: target)
        }

        let restored = ConversationCompactionLogic.historyForModel(store.messages)
        #expect(restored.map(\.id) == original.map(\.id))
    }

    @Test("Удалённое сообщение действительно исчезает из ленты")
    func removedMessageIsGone() {
        let store = MessageStore()
        let message = Message(role: .user, content: "Hello", isFinished: true)
        store.append(message)
        #expect(store.messages.contains { $0.id == message.id })
        #expect(store.remove(id: message.id))
        #expect(!store.messages.contains { $0.id == message.id })
        #expect(!store.remove(id: "missing-id"))
    }

    @Test("Детали сжатия подставляют оба числа")
    func detailsCarryBothNumbers() {
        let text = L.t(AppLocalizationKey.locModelSwitchCompactionDetails, "120k", "64k")
        #expect(text.contains("120k"))
        #expect(text.contains("64k"))
    }

    @Test("Восстановление модели при запуске не считается переключением")
    func modelRestorationIsNotASwitch() {
        // At launch the app restores the model — nothing was switched FROM,
        // so the chat must not be compacted behind the user's back.
        #expect(ModelSwitchCompactionLogic.notice(
            previousModel: "",
            newModel: "small",
            usedTokens: 120_000,
            limitTokens: 64_000,
            candidates: [],
            sessionID: "s1"
        ) == nil)
    }

    @Test("Выход с большим окном ищется во всех провайдерах")
    func alternativesSpanProviders() {
        let candidates = [
            ModelSwitchCompactionLogic.Candidate(
                id: "same-provider-big", window: 500_000, providerID: "p1", providerName: "One"
            ),
            ModelSwitchCompactionLogic.Candidate(
                id: "other-provider-huge", window: 1_000_000, providerID: "p2", providerName: "Two"
            ),
            ModelSwitchCompactionLogic.Candidate(
                id: "small", window: 8_192, providerID: "p2", providerName: "Two"
            )
        ]
        let fits = ModelSwitchCompactionLogic.modelsThatFit(
            usedTokens: 120_000,
            candidates: candidates
        )
        // The biggest window first, and the provider is part of the answer:
        // the escape hatch may live in another provider.
        #expect(fits.map(\.id) == ["other-provider-huge", "same-provider-big"])
        #expect(fits.map(\.providerID) == ["p2", "p1"])
        #expect(fits.first?.providerName == "Two")
        #expect(fits.first?.key == "p2::other-provider-huge")
    }

    @Test("Приложение собирает кандидатов из всех провайдеров")
    func appStateCollectsCandidatesFromEveryProvider() {
        let state = AppState()
        state.defaults = UserDefaults(suiteName: "mycoder.model-switch-candidates.tests")!
        state.customProviders = [
            CustomProvider(
                id: "small-provider",
                name: "Small",
                type: .openAI,
                baseURL: "https://small.example.com",
                apiKey: "",
                isEnabled: true,
                models: ["tiny-model-8k"],
                supportsTools: true,
                acpEnabled: false
            ),
            CustomProvider(
                id: "big-provider",
                name: "Big",
                type: .openAI,
                baseURL: "https://big.example.com",
                apiKey: "",
                isEnabled: true,
                models: ["huge-model-1m"],
                supportsTools: true,
                acpEnabled: false
            )
        ]
        let candidates = state.modelSwitchCompactionCandidates
        let tiny = candidates.first { $0.id == "tiny-model-8k" }
        let huge = candidates.first { $0.id == "huge-model-1m" }
        #expect(tiny?.providerID == "small-provider")
        #expect(tiny?.providerName == "Small")
        #expect(tiny?.window == 8_192)
        #expect(huge?.providerID == "big-provider")
        #expect(huge?.providerName == "Big")
        #expect(huge?.window == 1_000_000)
    }

    @Test("Сжатие требуется только при настоящем переключении модели")
    func requiresCompactionOnlyForRealSwitches() {
        #expect(ModelSwitchCompactionLogic.requiresCompaction(
            previousModel: "big", usedTokens: 120_000, limitTokens: 64_000
        ))
        #expect(!ModelSwitchCompactionLogic.requiresCompaction(
            previousModel: "big", usedTokens: 10, limitTokens: 64_000
        ))
        // The app restored its model at launch — nothing was switched from.
        #expect(!ModelSwitchCompactionLogic.requiresCompaction(
            previousModel: "", usedTokens: 120_000, limitTokens: 64_000
        ))
        // An unknown window never forces a compaction.
        #expect(!ModelSwitchCompactionLogic.requiresCompaction(
            previousModel: "big", usedTokens: 500_000, limitTokens: 0
        ))
    }

    @Test("Список альтернатив ограничен — меню не превращается в каталог всех моделей")
    func alternativesAreCapped() {
        let candidates = (0..<50).map { index in
            ModelSwitchCompactionLogic.Candidate(
                id: "model-\(index)",
                window: 500_000 + index,
                providerID: "p1",
                providerName: "One"
            )
        }
        let notice = ModelSwitchCompactionLogic.notice(
            previousModel: "big",
            newModel: "small",
            usedTokens: 120_000,
            limitTokens: 64_000,
            candidates: candidates,
            sessionID: "s1"
        )
        #expect(notice?.alternatives.count == ModelSwitchCompactionLogic.maxAlternatives)
        // The biggest windows come first.
        #expect(notice?.alternatives.first?.window == 500_049)
    }

    @Test("Уведомление создаётся только когда контекст не помещается")
    func noticeExistsOnlyWhenCompactionIsRequired() {
        #expect(ModelSwitchCompactionLogic.notice(
            previousModel: "big",
            newModel: "small",
            usedTokens: 10,
            limitTokens: 100,
            candidates: [],
            sessionID: "s1"
        ) == nil)

        let notice = ModelSwitchCompactionLogic.notice(
            previousModel: "big",
            newModel: "small",
            usedTokens: 120_000,
            limitTokens: 64_000,
            candidates: [
                ModelSwitchCompactionLogic.Candidate(id: "huge", window: 1_000_000, providerID: "p2", providerName: "Two"),
                ModelSwitchCompactionLogic.Candidate(id: "medium", window: 200_000, providerID: "p1", providerName: "One")
            ],
            sessionID: "s1"
        )
        #expect(notice?.phase == .pending)
        #expect(notice?.previousModel == "big")
        #expect(notice?.newModel == "small")
        #expect(notice?.usedTokens == 120_000)
        #expect(notice?.limitTokens == 64_000)
        #expect(notice?.sessionID == "s1")
        // The escape hatch: models that hold the current context untouched.
        #expect(notice?.alternatives.map(\.id) == ["huge", "medium"])
        #expect(notice?.alternatives.map(\.providerID) == ["p2", "p1"])
        #expect(notice?.canStop == true)
        #expect(notice?.canRollback == false)
        #expect(notice?.canRetry == false)
    }

    @Test("Откат удаляет только сводку и заметку о сжатии")
    func rollbackTargetsOnlyCompactionMessages() {
        #expect(ModelSwitchCompactionLogic.rollbackTargets(
            summaryMessageID: "summary",
            noticeMessageID: "notice"
        ) == ["notice", "summary"])
        #expect(ModelSwitchCompactionLogic.rollbackTargets(
            summaryMessageID: "summary",
            noticeMessageID: nil
        ) == ["summary"])
        #expect(ModelSwitchCompactionLogic.rollbackTargets(
            summaryMessageID: nil,
            noticeMessageID: nil
        ).isEmpty)
    }

    @Test("Фаза уведомления следует за результатом сжатия")
    func phaseFollowsCompactionOutcome() {
        #expect(ModelSwitchCompactionLogic.phase(for: .compacted(
            summaryMessageID: "s",
            noticeMessageID: "n",
            beforeTokens: 100,
            afterTokens: 20
        )) == .compacted)
        #expect(ModelSwitchCompactionLogic.phase(for: .cancelled) == .cancelled)
        #expect(ModelSwitchCompactionLogic.phase(for: .failed("boom")) == .failed)
        #expect(ModelSwitchCompactionLogic.phase(for: .unsupported("server keeps history")) == .failed)
        #expect(ModelSwitchCompactionLogic.phase(for: .nothingToCompact) == .failed)
    }

    @Test("Пока сжатие идёт, отправка ждёт его окончания")
    func sendWaitsForRunningCompaction() {
        #expect(ModelSwitchCompactionLogic.blocksSend(phase: .pending))
        #expect(ModelSwitchCompactionLogic.blocksSend(phase: .running))
        #expect(!ModelSwitchCompactionLogic.blocksSend(phase: .compacted))
        #expect(!ModelSwitchCompactionLogic.blocksSend(phase: .cancelled))
        #expect(!ModelSwitchCompactionLogic.blocksSend(phase: .failed))
        #expect(!ModelSwitchCompactionLogic.blocksSend(phase: .rolledBack))
    }

    @Test("После сжатия уведомление можно откатить, после отката — повторить")
    func noticeFlagsFollowThePhase() {
        var notice = ModelSwitchCompactionNotice(
            previousModel: "big",
            newModel: "small",
            usedTokens: 120_000,
            limitTokens: 64_000,
            phase: .compacted,
            alternatives: [
                ModelSwitchCompactionLogic.Candidate(id: "huge", window: 1_000_000, providerID: "p1", providerName: "One")
            ],
            summaryMessageID: "summary",
            noticeMessageID: "notice",
            error: nil,
            sessionID: "s1"
        )
        #expect(notice.canRollback)
        #expect(!notice.canStop)
        #expect(!notice.canRetry)

        notice.phase = .rolledBack
        notice.summaryMessageID = nil
        notice.noticeMessageID = nil
        #expect(!notice.canRollback)
        #expect(notice.canRetry)

        notice.phase = .cancelled
        #expect(notice.canRetry)
        #expect(!notice.canStop)
    }

    @Test("Повтор не предлагается, когда провайдер вообще не умеет сжимать")
    func unsupportedProviderIsNotRetryable() {
        var notice = ModelSwitchCompactionNotice(
            previousModel: "big",
            newModel: "small",
            usedTokens: 120_000,
            limitTokens: 64_000,
            phase: .failed,
            alternatives: [],
            summaryMessageID: nil,
            noticeMessageID: nil,
            error: "history is kept on the server",
            sessionID: "s1"
        )
        #expect(notice.canRetry)
        notice.retryable = false
        #expect(!notice.canRetry)
    }
}
