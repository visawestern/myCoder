import SwiftUI


struct MessageRow: View {
    let message: Message
    var projectRoot: String = ""
    /// Outlined while a notification tap is walking the user to this row.
    var isHighlighted: Bool = false
    /// Rows live in a LazyVStack keyed by message id, so their stored inputs
    /// do not change on a theme switch. Reading `colorScheme` directly makes
    /// every visible row re-evaluate its palette (and its cards) instead of
    /// keeping the old black surface or white text.
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var showRawText = false
    @State private var showCompiledContext = false

    /// The sheet content is derived from the message itself — the persisted
    /// `.compiledContext` part and `contextSummary`. Transient `@State` could
    /// be empty exactly when the sheet is presented (row recreated, session
    /// reloaded), which is how the user got an empty "Контекст" window.
    private var contextSheetContent: MessageContextSheetLogic.Content {
        MessageContextSheetLogic.content(for: message)
    }

    private var displayTexts: [String] {
        let partTexts = message.parts.compactMap { part -> String? in
            if case .text(let text) = part { return text }
            return nil
        }
        return MessageContentSanitizerLogic.displayTexts(
            partTexts: partTexts,
            fallback: message.content
        )
    }

    private var messageText: String {
        displayTexts.joined(separator: "\n\n")
    }

    /// Картинки сообщения для коллажа (C5): `.image`-части или legacy
    /// вложения. Пустые картинки отбрасываются.
    ///
    /// Вход: `message`.
    /// Выход: массив `ClipboardImage` в порядке частей.
    /// Зависимости: `MessageDisplayLogic.imagesForDisplay`.
    private var messageImages: [ClipboardImage] {
        MessageDisplayLogic.imagesForDisplay(message)
    }

    private var reasoningText: String {
        let base = MessageResponseMergeLogic.reasoningForDisplay(message)
        if !base.isEmpty { return base }
        // Models that inline <think> blocks (Qwen/DeepSeek-style free
        // routers) carry no separate reasoning channel — surface the
        // extracted thinking in the spoiler instead of leaking tags.
        return ThinkTagLogic.inlineThinking(in: rawJoinedText)
    }

    /// Unsanitized answer text for think extraction (display text already
    /// has the blocks stripped, so it can never be the source).
    private var rawJoinedText: String {
        let partTexts = message.parts.compactMap { part -> String? in
            if case .text(let text) = part { return text }
            return nil
        }
        return (partTexts.isEmpty ? [message.content] : partTexts).joined(separator: "\n\n")
    }

    private var reasoningBlocks: [String] {
        let fromParts = message.parts.compactMap { part -> String? in
            if case .reasoning(let text) = part, !text.isEmpty { return text }
            return nil
        }
        if !fromParts.isEmpty { return fromParts }
        let legacy = reasoningText
        return legacy.isEmpty ? [] : [legacy]
    }

    private var showsThinkingSpoiler: Bool {
        message.role == .assistant
            && (!reasoningBlocks.isEmpty || (message.isStreaming && !MessageDisplayLogic.hasVisibleAnswer(message)))
    }

    private var isThinkingInProgress: Bool {
        message.isStreaming && !MessageDisplayLogic.hasVisibleAnswer(message)
    }

    private var showsActionBar: Bool {
        MessageEditLogic.shouldShowActions(
            hasToolCalls: hasToolCalls,
            isStreaming: message.isStreaming,
            canEdit: MessageEditLogic.canEdit(message),
            displayText: messageText,
            hasAttachments: !(message.files ?? []).isEmpty
                || !MessageDisplayLogic.attachedImagesForDisplay(message).isEmpty
                || MessageDisplayLogic.hasImageParts(message)
        )
    }

    private var hasToolCalls: Bool {
        message.parts.contains {
            if case .toolCall = $0 { return true }
            return false
        }
    }

    private var isTrailing: Bool {
        MessageRowLayoutLogic.isTrailing(role: message.role)
    }

    /// Resolved image paths found in the message's text (plan item 13.1).
    /// Uses the display text, so protocol blocks are already stripped.
    private var inlineImagePaths: [String] {
        ChatImagePathLogic.extractImagePaths(
            from: messageText,
            projectRoot: projectRoot.isEmpty ? nil : projectRoot
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isTrailing {
                // Telegram-style: user bubble hugs the trailing edge.
                Spacer(minLength: 40)

                VStack(alignment: .trailing, spacing: MessageRowLayoutLogic.actionBarSpacing) {
                    messageContent

                    if showsActionBar {
                        messageActions
                    }
                }
                .frame(maxWidth: MessageRowLayoutLogic.userBubbleMaxWidth, alignment: .trailing)

                Image(systemName: "person.circle").interfaceFont(size: 14).foregroundColor(Color.mimo.cyan).frame(width: 20)
            } else {
                if message.role == .assistant {
                    Image(systemName: "sparkle").interfaceFont(size: 14).foregroundColor(Color.mimo.brand).frame(width: 20)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if let routeChips = webRouteChips, !routeChips.isEmpty {
                        RouteChipsView(chips: routeChips)
                    }
                    if showsThinkingSpoiler, reasoningBlocks.isEmpty {
                        ThinkingSpoilerView(
                            reasoning: reasoningText,
                            duration: message.reasoningDuration,
                            isThinking: isThinkingInProgress
                        )
                    }
                    messageContent

                    if showsActionBar {
                        HStack(spacing: 0) {
                            messageActions
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer().frame(width: 20)
            }
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.mimo.brand.opacity(isHighlighted ? 0.10 : 0))
                .padding(.horizontal, 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.mimo.brand.opacity(isHighlighted ? 0.55 : 0), lineWidth: 1.5)
                .padding(.horizontal, 8)
        )
        .animation(.easeInOut(duration: 0.25), value: isHighlighted)
        .sheet(isPresented: $showCompiledContext) {
            CompiledContextSheet(
                text: contextSheetContent.text,
                fallback: contextSheetContent.fallback
            )
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        // Raw mode replaces the rendered body with the captured wire events.
        if showRawText {
            VStack(alignment: .leading, spacing: 8) {
                rawTextBubble
                ForEach(message.pendingApprovals) { approval in
                    approvalCard(approval)
                }
            }
        } else {
            formattedContent
        }

    }

    @ViewBuilder
    private var formattedContent: some View {
        // Вердикт проверки цели — чип со спойлером, а не сырой JSON
        // (жалоба владельца 2026-11-09).
        if message.role == .assistant,
           let verdict = GoalVerdictPresentationLogic.presentation(in: messageText) {
            GoalVerdictCard(presentation: verdict)
        // Системное сообщение с чипом отката рендерится как оранжевый чип,
        // а не как сырой текст маркера.
        } else if message.role == .system, message.content.hasPrefix(RollbackChipCodec.marker) {
            RollbackChipMessageView(content: message.content)
        } else if messageImages.isEmpty {
            ForEach(contentSegments) { segment in
                segmentView(segment)
            }
        } else {
            contentWithImages
        }

        if let approvalID = message.pendingApprovalID,
           let tool = message.pendingApprovalTool {
            WebToolApprovalCardView(
                approvalID: approvalID,
                tool: tool,
                message: message.pendingApprovalMessage ?? ""
            )
        }

        // Пункт 13.1: пути-картинки из текста — превью под контентом.
        if !inlineImagePaths.isEmpty {
            ChatImagePathCollageView(paths: inlineImagePaths)
                .padding(.top, 2)
        }

        if let added = message.tokensAdded, let removed = message.tokensRemoved, added + removed > 0 {
            FileChangeSummaryRow(path: message.agentName ?? "Changes", additions: added, deletions: removed)
        }

        // Кнопка «Контекст» показывается всегда: либо с собранным пакетом
        // (часть .compiledContext выше), либо с честной причиной отсутствия.
        if let summary = message.contextSummary,
           !message.parts.contains(where: {
               if case .compiledContext = $0 { return true }
               return false
           }) {
            contextSummaryButton(summary)
        }

        if let info = message.sendInfo {
            MessageSendInfoFooter(info: info)
        }
    }

    /// Контент сообщения вместе с коллажем картинок (C5).
    ///
    /// У пользовательского сообщения коллаж стоит СЛЕВА от текста — так
    /// вложение не отрывается от вопроса. У остальных ролей коллаж идёт под
    /// контентом. `.image`-части исключены из вертикального потока, иначе они
    /// дублировались бы под текстом.
    ///
    /// Вход: `contentSegments`, `messageImages`, `isTrailing`.
    /// Выход: HStack/VStack с коллажем и сегментами сообщения.
    /// Зависимости: `MessageImageCollageView`, `segmentView`.
    @ViewBuilder
    private var contentWithImages: some View {
        let segments = contentSegments
        if isTrailing {
            HStack(alignment: .top, spacing: 8) {
                MessageImageCollageView(images: messageImages)
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(segments) { segment in
                        segmentView(segment)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(segments) { segment in
                    segmentView(segment)
                }
            }
            MessageImageCollageView(images: messageImages)
        }
    }

    /// Один сегмент содержимого сообщения.
    ///
    /// Вход: `segment` — часть текста, reasoning, tool-call или approval.
    /// Выход: соответствующее представление.
    /// Зависимости: `partView`, `ThinkingSpoilerView`,
    /// `SplitToolInspectorView`, `approvalCard`.
    @ViewBuilder
    private func segmentView(_ segment: MessageContentSegment) -> some View {
        switch segment {
        case .part(let part):
            partView(part)
        case .reasoning(let blocks):
            ThinkingSpoilerView(
                reasoning: blocks.joined(separator: "\n\n"),
                duration: message.reasoningDuration,
                isThinking: isThinkingInProgress
            )
        case .toolCalls(let calls):
            if calls.contains(where: isPendingQuestion) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(calls) { call in
                        toolCallPartView(call)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SplitToolInspectorView(
                    steps: calls,
                    messageID: message.id,
                    isMessageStreaming: message.isStreaming
                )
            }
        case .approval(let approval):
            approvalCard(approval)
        }
    }

    private func approvalCard(_ approval: PendingToolApproval) -> some View {
        WebToolApprovalCardView(
            approvalID: approval.id,
            tool: approval.tool,
            message: approval.message,
            notificationName: .localToolApprovalResolved
        )
    }

    /// Raw unformatted answer: single selectable Text so the whole reply can
    /// be selected/copied as plain text in the same bubble.
    private var rawTextBubble: some View {
        ScrollView {
            Text(TurnPresentation.rawText(events: message.rawResponses, fallback: messageText))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color.mimo.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mimo.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var messageActions: some View {
        HStack(spacing: 2) {
            if !messageText.isEmpty {
                MessageActionButton(
                    icon: copied ? "checkmark" : "doc.on.doc",
                    tooltip: copied ? L.t(AppLocalizationKey.locCopied) : L.t(AppLocalizationKey.locCopyAll),
                    isActive: copied
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(messageText, forType: .string)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                }
            }

            // Raw/formatted toggle, next to resend/retry: swaps the rendered
            // answer for the raw wire response and back (user directive
            // 2026-11-03, п.3). It no longer exists to make the text
            // selectable — that job is gone. It sits outside the copy block
            // so a message with only raw events can still be switched.
            if RawAnswerToggleLogic.canToggle(
                messageText: messageText,
                rawEvents: message.rawResponses
            ) {
                MessageActionButton(
                    icon: RawAnswerToggleLogic.icon(isRaw: showRawText),
                    tooltip: L.t(RawAnswerToggleLogic.tooltipKey(isRaw: showRawText)),
                    isActive: showRawText
                ) {
                    withAnimation { showRawText = RawAnswerToggleLogic.toggled(isRaw: showRawText) }
                }
            }

            if MessageEditLogic.canEdit(message) {
                MessageActionButton(icon: "pencil", tooltip: "Edit") {
                    NotificationCenter.default.post(
                        name: .editMessage,
                        object: nil,
                        userInfo: ["messageId": message.id]
                    )
                }

                if MessageEditLogic.canResend(message) {
                    MessageActionButton(
                        icon: message.role == .user ? "arrow.up.circle" : "arrow.counterclockwise",
                        tooltip: message.role == .user ? L.t(AppLocalizationKey.locResend) : L.t(AppLocalizationKey.locRetry)
                    ) {
                        let name: Notification.Name = message.role == .user ? .resendMessage : .retryMessage
                        NotificationCenter.default.post(
                            name: name,
                            object: nil,
                            userInfo: ["messageId": message.id]
                        )
                    }
                }
            }

            // Откат диалога к этому запросу пользователя: возвращает состояние
            // чата и файлов к моменту запроса (через RollbackCoordinator).
            if message.role == .user && !message.isStreaming {
                MessageActionButton(icon: "arrow.uturn.backward", tooltip: L.t("Roll back to this request")) {
                    NotificationCenter.default.post(
                        name: .rollbackRequested,
                        object: nil,
                        userInfo: ["messageId": message.id]
                    )
                }
            }
        }
        .padding(4)
        .background(Color.mimo.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.mimo.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func partView(_ part: MessagePartContent) -> some View {
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

    /// The point context that was compiled locally for this message — the
    /// button opens it in full (user directive D2: no summary).
    @ViewBuilder
    private func compiledContextButton(_ text: String) -> some View {
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
    @ViewBuilder
    private func contextSummaryButton(_ summary: String) -> some View {
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

    @ViewBuilder
    private func toolCallPartView(_ call: ToolCallInspectorStep) -> some View {
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

    private func toolCallSpoiler(_ call: ToolCallInspectorStep) -> some View {
        SplitToolInspectorView(
            steps: [call],
            messageID: message.id,
            isMessageStreaming: message.isStreaming
        )
    }

    private func isPendingQuestion(_ call: ToolCallInspectorStep) -> Bool {
        PlanQuestionLogic.isQuestionTool(call.name) && call.result == nil
    }

    private var contentSegments: [MessageContentSegment] {
        MessageContentSegment.build(
            from: MessageRowPartsLogic.displayParts(
                parts: MessageDisplayLogic.withoutImageParts(
                    MessageDisplayLogic.chatDisplayParts(message.parts)
                ),
                content: message.content
            ),
            approvals: message.pendingApprovals
        )
    }

    /// Route metadata chips (provider/model/effort/remote chat) from a web
    /// provider turn. Rendered in the header, never in the answer text
    /// (user directive 2026-09-08).
    private var webRouteChips: [String]? {
        message.parts.compactMap { part -> [String]? in
            if case .routeInfo(let chips) = part { return chips }
            return nil
        }.first
    }

    /// Markdown-пузырь текстовой части сообщения (вынесен в отдельный
    /// компонент `MessageRowMarkdownView` — см. его документацию).
    ///
    /// Вход: `text` — очищенная проза.
    /// Выход: пузырь с прозой, кодом и инлайн-картинками.
    /// Зависимости: `MessageRowMarkdownView`.
    private func markdownBubble(_ text: String) -> some View {
        MessageRowMarkdownView(
            text: text,
            isUser: message.role == .user,
            projectRoot: projectRoot.isEmpty ? nil : projectRoot,
            isLightInterface: colorScheme == .light
        )
    }
}


