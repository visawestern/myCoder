import SwiftUI

/// Расширение `MessageRow`: рендер отдельных частей содержимого
/// сообщения (text/reasoning/tool-call/compiled-context/image). Вынесено
/// из `MessageRowView.swift`, чтобы держать файл под лимитом 600 строк.
extension MessageRow {
    /// Одна часть содержимого сообщения.
    ///
    /// Вход: `part` — часть `MessagePartContent`.
    /// Выход: соответствующее представление (пузырь markdown, спойлер
    /// reasoning, кнопка контекста, картинка; служебные шаги — EmptyView).
    /// Зависимости: `markdownBubble`, `ThinkingSpoilerView`,
    /// `compiledContextButton`, `TappableChatImage`, `MessageDisplayLogic`.
    @ViewBuilder
    func partView(_ part: MessagePartContent) -> some View {
        switch part {
        case .text(let text):
            if let sanitized = MessageContentSanitizerLogic.sanitizedTextPart(text) {
                markdownBubble(sanitized)
            }
        case .reasoning(let text):
            if !text.isEmpty {
                ThinkingSpoilerView(
                    reasoning: text,
                    duration: nil,
                    isThinking: message.isStreaming && !MessageDisplayLogic.hasVisibleAnswer(message)
                )
            }
        case .stepStart, .stepFinish:
            EmptyView()
        case .toolCall:
            EmptyView()
        case .routeInfo:
            EmptyView()
        case .compiledContext(let text):
            compiledContextButton(text)
        case .image(let base64, let mimeType):
            if !base64.isEmpty {
                TappableChatImage(image: ClipboardImage(base64: base64, mimeType: mimeType))
            }
        }
    }

    /// Кнопка «Контекст» для собранного пакета (часть `.compiledContext`).
    ///
    /// Вход: `text` — содержимое пакета.
    /// Выход: капсула, открывающая `CompiledContextSheet`.
    /// Зависимости: `showCompiledContext`, `AppLocalizationKey`.
    @ViewBuilder
    func compiledContextButton(_ text: String) -> some View {
        if !text.isEmpty {
            Button {
                showCompiledContext = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(L.t(AppLocalizationKey.locShowCompiledContext))
                }
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.brand)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.mimo.brand.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(HandCursorButtonStyle())
        }
    }

    /// Честная кнопка «Контекст», когда пакет не собран: показывает причину
    /// (первый промпт, чат без проекта, нет соответствий, ошибка) вместо
    /// пустого окна (user complaint 2026-10-30).
    ///
    /// Вход: `summary` — текст причины.
    /// Выход: капсула с тултипом причины.
    /// Зависимости: `showCompiledContext`, `AppLocalizationKey`.
    @ViewBuilder
    func contextSummaryButton(_ summary: String) -> some View {
        Button {
            showCompiledContext = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.magnifyingglass")
                Text(L.t(AppLocalizationKey.locShowCompiledContext))
            }
            .interfaceFont(size: 11, weight: .medium)
            .foregroundColor(Color.mimo.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.mimo.subtleFill)
            .clipShape(Capsule())
        }
        .buttonStyle(HandCursorButtonStyle())
        .help(summary)
    }

    /// Специальная карточка для plan-тула с вопросами: `PlanQuestionCardView`
    /// вместо спойлера сырого JSON (жалоба владельца 2026-11-09).
    ///
    /// Вход: `call` — шаг вызова.
    /// Выход: карточка вопросов или спойлер.
    /// Зависимости: `PlanQuestionLogic`, `PlanQuestionCardView`.
    @ViewBuilder
    func toolCallPartView(_ call: ToolCallInspectorStep) -> some View {
        if PlanQuestionLogic.isQuestionTool(call.name), call.result == nil {
            let questions = PlanQuestionLogic.parseQuestions(from: call.args)
            if !questions.isEmpty {
                PlanQuestionCardView(questions: questions) { answers in
                    NotificationCenter.default.post(
                        name: .submitPlanQuestionAnswers,
                        object: nil,
                        userInfo: ["answers": answers]
                    )
                }
            } else {
                toolCallSpoiler(call)
            }
        } else {
            toolCallSpoiler(call)
        }
    }

    /// Спойлер одного вызова инструмента.
    ///
    /// Вход: `call` — шаг вызова.
    /// Выход: `SplitToolInspectorView` с одним шагом.
    /// Зависимости: `SplitToolInspectorView`.
    func toolCallSpoiler(_ call: ToolCallInspectorStep) -> some View {
        SplitToolInspectorView(
            steps: [call],
            messageID: message.id,
            isMessageStreaming: message.isStreaming
        )
    }

    /// Является ли шаг «plan-вопросом» без ответа.
    ///
    /// Вход: `call` — шаг вызова.
    /// Выход: true — показать карточку вопросов.
    /// Зависимости: `PlanQuestionLogic`.
    func isPendingQuestion(_ call: ToolCallInspectorStep) -> Bool {
        PlanQuestionLogic.isQuestionTool(call.name) && call.result == nil
    }
}
