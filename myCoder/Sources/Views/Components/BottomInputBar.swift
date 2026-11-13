import SwiftUI
import AppKit

struct BottomInputBar: View {
    @Environment(\.interfaceFontScale) private var interfaceFontScale
    @Binding var messageText: String
    let onSend: () -> Void
    let onStop: () -> Void
    var isLoading: Bool = false
    @ObservedObject var attachmentStore: MessageAttachmentStore
    @Binding var showFilePicker: Bool
    @ObservedObject var messageQueue: MessageQueue
    var contextUsage: ContextUsage? = nil
    /// True while the host compiles the point context for the outgoing message.
    var isCompilingContext: Bool = false
    var contextPreparationStage: String = ""
    /// True while the chat's message history is being loaded (first open of a
    /// session or an older-page fetch). Shown as a status line like the
    /// context-compiling line, so loading is never invisible.
    var isLoadingMessages: Bool = false
    var onForceSendQueued: (QueuedMessage) -> Void = { _ in }
    var onEditQueued: (QueuedMessage) -> Void = { _ in }
    @EnvironmentObject var appState: AppState
    @State private var showPlusMenu = false
    @State private var showPhotoPicker = false
    
    private var canSend: Bool {
        SendReadinessLogic.canSendMessage(
            text: messageText,
            images: attachmentStore.attachedImages,
            files: attachmentStore.attachedFiles,
            modelID: appState.effectiveSelectedModel(),
            providerID: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID,
            serverConnected: appState.serverConnected,
            customProviders: appState.customProviders,
            localProviderIDs: appState.localProviderIDs,
            webProviderIDs: appState.webProviderIDs,
            serverProviderIDs: appState.serverProviders.map(\.id),
            webConnected: WebProviderConnectivity.configID(fromOptionID: appState.selectedProviderID) == nil
                ? nil
                : appState.selectedProviderConnected
        )
    }

    /// A second send while the context is still compiling would race with the
    /// first. The composer keeps the text and the loader explains the wait.
    private var canSendNow: Bool { canSend && !isCompilingContext }

    /// Goal scope of the open chat: its own project wins over the selected
    /// workspace; a standalone chat has no project (goal stays chat-bound).
    private var goalContext: GoalContext {
        GoalContextLogic.context(
            chatID: appState.selectedSession?.id,
            sessionDirectory: appState.selectedSession?.directory,
            selectedWorkspacePath: appState.selectedWorkspace?.path
        )
    }

    /// Round 8 P1: why sending is blocked, surfaced to the user.
    private var sendReason: String? {
        SendReadinessReason.reason(
            text: messageText,
            images: attachmentStore.attachedImages,
            files: attachmentStore.attachedFiles,
            modelID: appState.selectedModel,
            providerID: appState.selectedProviderID.isEmpty ? nil : appState.selectedProviderID,
            serverConnected: appState.serverConnected,
            customProviders: appState.customProviders,
            localProviderIDs: appState.localProviderIDs,
            webProviderIDs: appState.webProviderIDs,
            serverProviderIDs: appState.serverProviders.map(\.id),
            webConnected: WebProviderConnectivity.configID(fromOptionID: appState.selectedProviderID) == nil
                ? nil
                : appState.selectedProviderConnected,
            effectiveModelID: appState.effectiveSelectedModel()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !messageQueue.pendingMessages.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(messageQueue.pendingMessages.enumerated()), id: \.element.id) { index, queued in
                        PendingMessageCard(
                            queued: queued,
                            index: index,
                            onForceSend: { onForceSendQueued(queued) },
                            onEdit: { onEditQueued(queued) },
                            onCancel: { messageQueue.cancelPending(at: index) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                Divider()
            }

            // The status line is an upward spoiler over the full
            // context-assembly journal (user directive 2026-11-07): one line
            // with the current action, and every action of the run behind it.
            ContextAssemblyStatusPanel(
                log: appState.contextAssemblyLog,
                isCompiling: isCompilingContext,
                currentStage: contextPreparationStage,
                isLoadingMessages: isLoadingMessages
            )

            GoalStatusPanel(context: goalContext)

            CompactMessageTextField(
                text: $messageText,
                placeholder: MiMoCopy.followUpPlaceholder(language: appState.appLanguage),
                onSubmit: {
                    guard SendButtonActivationLogic.canInvokeSend(canSend: canSendNow, isLoading: isLoading) else { return }
                    onSend()
                },
                compactSingleLine: messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                focusRequest: appState.inputFocusRequest
            )
            .padding(.vertical, 4)
            // Context ring lives in the top-right corner of the input card and
            // never occupies its own line (user directive 2026-10-24). In
            // point-context mode the harness manages the budget itself, so the
            // ring is hidden (plan item 9: the ring only shows when point
            // context is OFF).
            .overlay(alignment: .topTrailing) {
                if let contextUsage, !appState.isPointContextEnabled {
                    ContextUsageIndicator(usage: contextUsage)
                        .padding(.trailing, 10)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if appState.inputDropdownEnabled {
                    InputCommandDropdownView(
                        messageText: $messageText,
                        contextProvider: { appState.inputDropdownContext() },
                        onInsert: { appState.inputFocusRequest += 1 }
                    )
                    // Float the palette above the input field.
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: -44)
                }
            }

            if let reason = sendReason, !isLoading,
               reason != "Type a message or attach a file to send." {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.error)
                    Text(reason)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.error)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            MessageInputToolbar(
                messageText: $messageText,
                showFilePicker: $showFilePicker,
                showPlusMenu: $showPlusMenu,
                showPhotoPicker: $showPhotoPicker,
                isLoading: isLoading,
                canSend: canSendNow,
                onSend: onSend,
                onStop: onStop,
                disabledReason: sendReason
            )
            .padding(.vertical, InputLayout.toolbarVerticalPadding(scale: interfaceFontScale))
        }
        .padding(.horizontal, InputLayout.cardContentPadding)
        .background(Color.mimo.surface)
        .overlay(Rectangle().fill(Color.mimo.border).frame(height: 1), alignment: .top)
        .messageAttachmentImportZone(store: attachmentStore)
        .fileImporter(isPresented: $showPhotoPicker, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    if let data = try? Data(contentsOf: url),
                       let nsImage = NSImage(data: data) {
                        attachmentStore.importResult(ClipboardPasteResult(images: [ClipboardImage(nsImage: nsImage)]))
                    }
                }
            }
        }
    }
}
