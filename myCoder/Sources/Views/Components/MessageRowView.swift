import SwiftUI

private enum MessageContentSegment: Identifiable {
    case part(MessagePartContent)
    case toolCalls([ToolCallInspectorStep])
    case approval(PendingToolApproval)

    var id: String {
        switch self {
        case .part(let part):
            return "part-\(part.id)"
        case .toolCalls(let calls):
            return "tools-\(calls.first?.id ?? "empty")"
        case .approval(let approval):
            return "approval-\(approval.id)"
        }
    }

    static func build(
        from parts: [MessagePartContent],
        approvals: [PendingToolApproval] = []
    ) -> [MessageContentSegment] {
        var segments: [MessageContentSegment] = []
        var calls: [ToolCallInspectorStep] = []
        var remainingApprovals = approvals

        func flushCalls() {
            guard !calls.isEmpty else { return }
            segments.append(.toolCalls(calls))
            calls = []
        }

        for part in parts {
            if case .routeInfo = part {
                // Route chips render in the header, not in the content flow.
                continue
            }
            if case .toolCall(let name, let args, let result, let callID) = part {
                let step = ToolCallInspectorStep(
                    id: part.id,
                    name: name,
                    args: args,
                    result: result
                )
                if let callID,
                   let approvalIndex = remainingApprovals.firstIndex(where: { $0.callID == callID }) {
                    // Keep the card directly after its own call instead of
                    // after the whole grouped tool spoiler.
                    flushCalls()
                    segments.append(.toolCalls([step]))
                    segments.append(.approval(remainingApprovals.remove(at: approvalIndex)))
                } else {
                    calls.append(step)
                }
            } else {
                flushCalls()
                segments.append(.part(part))
            }
        }
        flushCalls()
        for approval in remainingApprovals {
            segments.append(.approval(approval))
        }
        return segments
    }
}

struct MessageRow: View {
    let message: Message
    var projectRoot: String = ""
    @State private var copied = false
    @State private var showRawText = false

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
    }

    @ViewBuilder
    private var messageContent: some View {
        // Raw mode: one contiguous selectable bubble — formatted bubbles are
        // heterogeneous views, so whole-answer selection only works here.
        if showRawText, !messageText.isEmpty {
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
        if !hasRenderableTextParts && !message.content.isEmpty {
            if let sanitized = MessageContentSanitizerLogic.sanitizedTextPart(message.content) {
                markdownBubble(sanitized)
            }
        }

        ForEach(contentSegments) { segment in
            switch segment {
            case .part(let part):
                partView(part)
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

        if let approvalID = message.pendingApprovalID,
           let tool = message.pendingApprovalTool {
            WebToolApprovalCardView(
                approvalID: approvalID,
                tool: tool,
                message: message.pendingApprovalMessage ?? ""
            )
        }

        if let added = message.tokensAdded, let removed = message.tokensRemoved, added + removed > 0 {
            FileChangeSummaryRow(path: message.agentName ?? "Changes", additions: added, deletions: removed)
        }

        let legacyImages = MessageDisplayLogic.attachedImagesForDisplay(message)
        if !legacyImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(legacyImages) { img in
                        TappableChatImage(image: img, fillThumbnail: true)
                    }
                }
                .padding(.horizontal, 4)
            }
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
            Text(messageText)
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
                // Raw/formatted toggle in the same bubble: formatted views
                // are heterogeneous, so whole-answer selection only works
                // on the single contiguous raw text.
                MessageActionButton(
                    icon: showRawText ? "doc.richtext" : "doc.plaintext",
                    tooltip: showRawText ? L.t(AppLocalizationKey.locFormatted) : L.t(AppLocalizationKey.locRawText),
                    isActive: showRawText
                ) {
                    withAnimation { showRawText.toggle() }
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
        case .image(let base64, let mimeType):
            if !base64.isEmpty {
                TappableChatImage(image: ClipboardImage(base64: base64, mimeType: mimeType))
            }
        }
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
            from: MessageDisplayLogic.chatDisplayParts(message.parts),
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

    private var hasRenderableTextParts: Bool {
        message.parts.contains { part in
            if case .text(let text) = part {
                return MessageContentSanitizerLogic.sanitizedTextPart(text) != nil
            }
            return false
        }
    }

    @ViewBuilder
    private func markdownBubble(_ text: String) -> some View {
        // One selectable surface for the whole message: the per-block SwiftUI
        // renderer made each line its own selection island, so a drag could
        // never span a heading, a bullet and the next paragraph.
        SelectableMarkdownTextView(text: text, fontSize: 14, textColor: Color.mimo.textPrimary, projectRoot: projectRoot)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                message.role == .user
                    ? Color.mimo.brand.opacity(0.2)
                    : Color.mimo.surface
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Compact metadata chips shown above an assistant message produced through a
/// web provider (provider · model · effort · remote chat). Kept out of the
/// message content — the copy button copies only the model's answer.
struct RouteChipsView: View {
    let chips: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.mimo.surface.opacity(0.7))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.mimo.border, lineWidth: 0.5)
                        )
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ThinkingSpoilerView: View {
    let reasoning: String
    let duration: TimeInterval?
    let isThinking: Bool
    @State private var isExpanded = false

    private var canExpand: Bool {
        !reasoning.isEmpty
    }

    /// While the reply is still streaming the reasoning grows, so keep it fully
    /// visible. Only once the message is finished and the user has not expanded
    /// it do we collapse to the short preview.
    private var showsFull: Bool {
        isExpanded || isThinking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                guard canExpand else { return }
                withAnimation(SpoilerExpandLogic.animation) { isExpanded.toggle() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .interfaceFont(size: 10, weight: .semibold)
                        .rotationEffect(.degrees(showsFull ? 90 : 0))
                        .opacity(canExpand ? 1 : 0)
                        .frame(width: 10)

                    if isThinking {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "brain")
                            .interfaceFont(size: 11)
                    }

                    Text(L.t(AppLocalizationKey.locThinking))
                        .interfaceFont(size: 12, weight: .medium)

                    if let duration = duration, !isThinking {
                        Text(String(format: "%.1fs", duration))
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted.opacity(0.6))
                    }

                    Spacer(minLength: 0)
                }
                .foregroundColor(Color.mimo.thinking)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(HandCursorButtonStyle())
            .disabled(!canExpand && !isThinking)

            if canExpand {
                MarkdownText(text: reasoning, fontSize: 12, textColor: Color.mimo.thinking)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Collapsed: clip to a short preview (no native `...`
                    // truncation). Expanded/streaming: full height.
                    .frame(
                        height: showsFull ? nil : SpoilerExpandLogic.collapsedPreviewHeight(),
                        alignment: .top
                    )
                    .clipped()
            }
        }
        .background(Color.mimo.thinking.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mimo.thinking.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(SpoilerExpandLogic.animation, value: isExpanded)
        .animation(SpoilerExpandLogic.animation, value: isThinking)
    }
}


struct ColumnResizeHandle: View {
    @Binding var width: Double
    var minWidth: Double = 80
    var maxWidth: Double = 420
    @State private var dragStartWidth: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 9)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(hovering ? Color.mimo.brand.opacity(0.6) : Color.mimo.border.opacity(0.7))
                    .frame(width: 1)
            )
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        width = min(max(dragStartWidth! + value.translation.width, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
    }
}

struct SplitToolInspectorView: View {
    let steps: [ToolCallInspectorStep]
    let messageID: String
    let isMessageStreaming: Bool
    @State private var isExpanded = false
    @State private var selectedStepID: String?
    @AppStorage("com.mycoder.toolInspector.sidebarWidth") private var inspectorSidebarWidth: Double = 120

    private var selectedStep: ToolCallInspectorStep? {
        steps.first(where: { $0.id == selectedStepID }) ?? steps.first
    }

    private var isComplete: Bool {
        ToolCallInspectorLogic.isComplete(steps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .interfaceFont(size: 10, weight: .semibold)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 10)
                        Image(systemName: "wrench.and.screwdriver")
                            .interfaceFont(size: 11)
                        Text(ToolCallInspectorLogic.headerTitle(for: steps))
                            .interfaceFont(size: 12, weight: .medium, design: .monospaced)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundColor(Color.mimo.cyan)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HandCursorButtonStyle())

                Spacer(minLength: 4)

                if isExpanded {
                    HStack(spacing: 4) {
                        Text(isComplete ? L.t(AppLocalizationKey.locCompleted) : L.t(AppLocalizationKey.locRunning))
                            .interfaceFont(size: 10, weight: .medium)
                        if isComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .interfaceFont(size: 10)
                        } else {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                        }
                    }
                    .foregroundColor(isComplete ? Color.mimo.success : Color.mimo.cyan)

                    MessageActionButton(
                        icon: "stop.fill",
                        tooltip: "Stop"
                    ) {
                        NotificationCenter.default.post(name: .stopGeneration, object: nil)
                    }
                    .disabled(!isMessageStreaming)
                    .opacity(isMessageStreaming ? 1 : 0.45)

                    MessageActionButton(
                        icon: "arrow.counterclockwise",
                        tooltip: "Retry"
                    ) {
                        NotificationCenter.default.post(
                            name: .retryMessage,
                            object: nil,
                            userInfo: ["messageId": messageID]
                        )
                    }
                } else if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.success)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            if isExpanded, let selectedStep {
                Divider()

                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            Button {
                                selectedStepID = step.id
                            } label: {
                                inspectorStepRow(
                                    number: index + 1,
                                    step: step,
                                    isSelected: step.id == selectedStep.id
                                )
                            }
                            .buttonStyle(HandCursorButtonStyle())
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: inspectorSidebarWidth, alignment: .top)
                    .frame(minHeight: 120, alignment: .top)
                    .background(Color.mimo.surface.opacity(0.55))

                    ColumnResizeHandle(width: $inspectorSidebarWidth)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            detailBlock(
                                label: L.t(AppLocalizationKey.locArguments),
                                value: argumentsText(for: selectedStep)
                            )

                            if let result = selectedStep.result, !result.isEmpty {
                                Divider()
                                detailBlock(
                                    label: L.t(AppLocalizationKey.locResult),
                                    value: ToolCallPresentationLogic.formattedResult(result)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 320)
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        isExpanded = false
                    } label: {
                        Label(L.t(AppLocalizationKey.locCollapse), systemImage: "chevron.up")
                            .interfaceFont(size: 11, weight: .medium)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.textSecondary)

                    Spacer(minLength: 0)

                    inspectorAction(icon: "doc.on.doc", title: L.t(AppLocalizationKey.locCopyAll)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            ToolCallInspectorLogic.copyText(for: steps),
                            forType: .string
                        )
                    }
                    inspectorAction(icon: "arrow.counterclockwise", title: L.t(AppLocalizationKey.locRetry)) {
                        NotificationCenter.default.post(
                            name: .retryMessage,
                            object: nil,
                            userInfo: ["messageId": messageID]
                        )
                    }
                    inspectorAction(icon: "pencil", title: L.t(AppLocalizationKey.locEdit)) {
                        NotificationCenter.default.post(
                            name: .editMessage,
                            object: nil,
                            userInfo: ["messageId": messageID]
                        )
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.mimo.surface.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mimo.codeBg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.mimo.border.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(SpoilerExpandLogic.animation, value: isExpanded)
        .onAppear {
            if selectedStepID == nil {
                selectedStepID = steps.first?.id
            }
        }
    }

    private func argumentsText(for step: ToolCallInspectorStep) -> String {
        ToolCallPresentationLogic.argumentSections(from: step.args)
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n\n")
    }

    private func inspectorStepRow(
        number: Int,
        step: ToolCallInspectorStep,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text(String(number))
                .interfaceFont(size: 10, weight: .medium)
                .frame(width: 14)
            Text(step.name.capitalized)
                .interfaceFont(size: 11, weight: .medium)
                .lineLimit(1)
            Spacer(minLength: 4)
            if step.result == nil {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .interfaceFont(size: 9)
                    .foregroundColor(Color.mimo.success)
            }
        }
        .foregroundColor(Color.mimo.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(isSelected ? Color.mimo.brand.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    private func detailBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .interfaceFont(size: 11, weight: .semibold)
                .foregroundColor(Color.mimo.textMuted)

            ScrollView(.horizontal) {
                Text(value)
                    .interfaceFont(size: 11, design: .monospaced)
                    .foregroundColor(Color.mimo.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorAction(
        icon: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.textSecondary)
        }
        .buttonStyle(HandCursorButtonStyle())
    }
}

struct MessageActionButton: View {
    let icon: String
    let tooltip: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .interfaceFont(size: 11)
                .foregroundColor(isActive ? Color.mimo.success : Color.mimo.textMuted)
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.mimo.surfaceHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(HandCursorButtonStyle())
        .onHover { isHovering = $0 }
        .help(tooltip)
    }
}

struct FileChangeSummaryRow: View {
    let path: String
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textMuted)
            Text((path as NSString).lastPathComponent)
                .interfaceFont(size: 12, design: .monospaced)
                .foregroundColor(Color.mimo.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("+\(additions)")
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.success)
            Text("-\(deletions)")
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.error)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.mimo.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Interactive Allow/Deny card for a web-agent tool that needs user approval
/// before execution. The driver is blocked awaiting the verdict; the card
/// resolves the pending request through `webToolApprovalResolved` and the
/// chat panel forwards the answer to the driver's approval mailbox.
struct WebToolApprovalCardView: View {
    let approvalID: String
    let tool: String
    let message: String
    var notificationName: Notification.Name = .webToolApprovalResolved

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield")
                    .interfaceFont(size: 14)
                    .foregroundColor(Color.mimo.warning)
                Text("myCoder wants to run a restricted tool")
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                Spacer()
            }
            Text(message)
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button {
                    resolve(approved: true)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .interfaceFont(size: 11, weight: .bold)
                        Text("Allow")
                            .interfaceFont(size: 12, weight: .semibold)
                    }
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.mimo.success)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(HandCursorButtonStyle())
                .accessibilityIdentifier("toolApproval.allow")
                Button {
                    resolve(approved: false)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .interfaceFont(size: 11, weight: .bold)
                        Text("Deny")
                            .interfaceFont(size: 12, weight: .semibold)
                    }
                    .foregroundColor(Color.mimo.error)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.mimo.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.mimo.error, lineWidth: 1)
                    )
                }
                .buttonStyle(HandCursorButtonStyle())
                .accessibilityIdentifier("toolApproval.deny")
                Spacer()
            }
        }
        .padding(12)
        .background(Color.mimo.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mimo.warning.opacity(0.6), lineWidth: 1)
        )
    }

    private func resolve(approved: Bool) {
        // Resolve on the next run-loop turn: the Combine receiver resumes
        // the waiting turn and mutates MessageStore. Doing that inline from
        // the button action can re-enter SwiftUI's update and spin.
        let name = notificationName
        let id = approvalID
        let toolName = tool
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: name,
                object: nil,
                userInfo: [
                    "approvalID": id,
                    "tool": toolName,
                    "approved": approved
                ]
            )
        }
    }
}
