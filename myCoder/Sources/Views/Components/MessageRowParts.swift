import SwiftUI
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
    @State private var isExpanded: Bool
    @State private var selectedStepID: String?
    /// Подгруженные результаты тулов (память → БД). Шаги, у которых
    /// `result == nil`, но `hasStoredResult`, подгружаются лениво при
    /// первом раскрытии спойлера.
    @State private var loadedResults: [String: String] = [:]
    @State private var isLoadingResults = false
    @AppStorage("com.mycoder.toolInspector.sidebarWidth") private var inspectorSidebarWidth: Double = 120

    init(
        steps: [ToolCallInspectorStep],
        messageID: String,
        isMessageStreaming: Bool,
        initiallyExpanded: Bool = false
    ) {
        self.steps = steps
        self.messageID = messageID
        self.isMessageStreaming = isMessageStreaming
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    /// Шаги с подмешанными подгруженными результатами.
    private var displayedSteps: [ToolCallInspectorStep] {
        ToolCallRequestLogic.merge(results: loadedResults, into: steps)
    }

    private var selectedStep: ToolCallInspectorStep? {
        displayedSteps.first(where: { $0.id == selectedStepID }) ?? displayedSteps.first
    }

    private var isComplete: Bool {
        ToolCallInspectorLogic.isComplete(steps)
    }

    /// Ленивая дозагрузка результатов: только недостающие ключи, один
    /// пакетный запрос, результат сохраняется в `ToolResultStore`, чтобы
    /// повторные открытия не лезли в базу.
    private func loadMissingResults() {
        let keys = ToolCallRequestLogic.keysToLoad(steps)
        guard !keys.isEmpty, !isLoadingResults else { return }
        isLoadingResults = true
        Task { @MainActor in
            loadedResults = ToolResultLoader.load(for: steps)
            isLoadingResults = false
        }
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
                    // The step list is its own vertical scroll surface so many
                    // steps never get clipped — and a bottom padding keeps the
                    // last row from touching the footer (user directive
                    // 2026-10-29: "список действий налазиет на нижний спойлер").
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
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
                        }
                        .padding(.bottom, 10)
                    }
                    .frame(width: inspectorSidebarWidth, alignment: .top)
                    .frame(minHeight: 120, maxHeight: 320, alignment: .top)
                    .background(Color.mimo.surface.opacity(0.55))

                    ColumnResizeHandle(width: $inspectorSidebarWidth)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            detailBlock(
                                label: L.t(AppLocalizationKey.locArguments),
                                value: argumentsText(for: selectedStep)
                            )

                            // Результат: уже загруженный или подгруженный
                            // лениво; в ожидании — честный индикатор, при
                            // отсутствии — сообщение о недоступности.
                            if let result = ToolCallRequestLogic.displayResult(
                                for: selectedStep,
                                results: loadedResults
                            ), !result.isEmpty {
                                Divider()
                                detailBlock(
                                    label: L.t(AppLocalizationKey.locResult),
                                    value: ToolCallPresentationLogic.formattedResult(result)
                                )
                            } else if ToolCallRequestLogic.isPending(selectedStep, results: loadedResults) {
                                Divider()
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small).scaleEffect(0.7)
                                    Text(L.t(AppLocalizationKey.locLoadingResult))
                                        .interfaceFont(size: 11)
                                        .foregroundColor(Color.mimo.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            } else if ToolCallRequestLogic.isUnavailable(selectedStep, results: loadedResults) {
                                Divider()
                                Text(L.t(AppLocalizationKey.locResultUnavailable))
                                    .interfaceFont(size: 11)
                                    .foregroundColor(Color.mimo.textMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
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
                            ToolCallInspectorLogic.copyText(for: displayedSteps),
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
        .onChange(of: isExpanded) { expanded in
            if expanded { loadMissingResults() }
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
            if ToolCallInspectorLogic.isComplete([step]) {
                Image(systemName: "checkmark.circle.fill")
                    .interfaceFont(size: 9)
                    .foregroundColor(Color.mimo.success)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
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
