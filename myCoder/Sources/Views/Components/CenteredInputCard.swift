import SwiftUI
import AppKit

struct CenteredInputCard: View {
    @Environment(\.interfaceFontScale) private var interfaceFontScale
    @Binding var messageText: String
    let onSend: () -> Void
    let onStop: () -> Void
    var isLoading: Bool = false
    @ObservedObject var attachmentStore: MessageAttachmentStore
    @Binding var showFilePicker: Bool
    @ObservedObject var messageQueue: MessageQueue
    @EnvironmentObject var appState: AppState
    var requestInputFocus: Bool = false
    var autoGrow: Bool = false
    var maxTextHeight: CGFloat? = nil
    var onForceSendQueued: (QueuedMessage) -> Void = { _ in }
    var onEditQueued: (QueuedMessage) -> Void = { _ in }
    @State private var showWorkspaceDropdown = false
    @State private var showPlusMenu = false
    @State private var showPhotoPicker = false
    @State private var expansionProgress: CGFloat = 0
    @State private var hasAttemptedSend = false

    private var horizontalPadding: CGFloat {
        InputCardLayoutLogic.contentHorizontalPadding
    }

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

    /// Round 8 P1: human-readable reason sending is blocked, so the user sees
    /// WHY (instead of a silently disabled button).
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

    // Only show the "empty input" error after the user has actually tried to send.
    // Provider/model errors are always shown so the user knows how to unblock send.
    private var displayedReason: String? {
        guard let reason = sendReason else { return nil }
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmptyInputError = trimmed.isEmpty && attachmentStore.attachedImages.isEmpty && attachmentStore.attachedFiles.isEmpty
        if isEmptyInputError && !hasAttemptedSend { return nil }
        return reason
    }

    var body: some View {
        VStack(spacing: InputCardLayoutLogic.sectionSpacing) {
            if !messageQueue.pendingMessages.isEmpty {
                pendingQueueSection
                capsuleDivider
            }

            ComposerAttachmentPreview(store: attachmentStore)

            if !attachmentStore.attachedImages.isEmpty || !attachmentStore.attachedFiles.isEmpty {
                capsuleDivider
            }

            workspaceHeader
                .offset(y: InputCardLayoutLogic.headerExpansionOffset(progress: expansionProgress))
                .opacity(InputCardLayoutLogic.sectionOpacity(progress: expansionProgress))
                .frame(maxHeight: expansionProgress < 0.01 ? 0 : nil, alignment: .bottom)
                .clipped()

            capsuleDivider
                .opacity(InputCardLayoutLogic.sectionOpacity(progress: expansionProgress))

            inputCore

            capsuleDivider
                .opacity(InputCardLayoutLogic.sectionOpacity(progress: expansionProgress))

            if let reason = displayedReason, !isLoading {
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
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }

            MessageInputToolbar(
                messageText: $messageText,
                showFilePicker: $showFilePicker,
                showPlusMenu: $showPlusMenu,
                showPhotoPicker: $showPhotoPicker,
                isLoading: isLoading,
                canSend: canSend,
                onSend: onSend,
                onStop: onStop,
                disabledReason: sendReason
            )
            .offset(y: InputCardLayoutLogic.footerExpansionOffset(progress: expansionProgress))
            .opacity(InputCardLayoutLogic.sectionOpacity(progress: expansionProgress))
            .frame(maxHeight: expansionProgress < 0.01 ? 0 : nil, alignment: .top)
            .clipped()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(capsuleBackground)
        .clipShape(RoundedRectangle(cornerRadius: InputCardLayoutLogic.capsuleCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: InputCardLayoutLogic.capsuleCornerRadius, style: .continuous)
                .stroke(capsuleStroke, lineWidth: 1)
        )
        .shadow(color: Color.mimo.brand.opacity(0.14), radius: 24, x: 0, y: 12)
        .fixedSize(horizontal: false, vertical: !autoGrow)
        .onAppear {
            withAnimation(InputCardLayoutLogic.expansionAnimation) {
                expansionProgress = 1
            }
        }
        .messageAttachmentImportZone(store: attachmentStore)
        .fileImporter(isPresented: $showPhotoPicker, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    if let data = try? Data(contentsOf: url),
                       let nsImage = NSImage(data: data) {
                        let clipImage = ClipboardImage(nsImage: nsImage)
                        attachmentStore.importResult(ClipboardPasteResult(images: [clipImage]))
                    }
                }
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 6) {
            Button(action: { showWorkspaceDropdown.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .interfaceFont(size: 11)
                    Text(appState.selectedWorkspace?.name ?? L.t(AppLocalizationKey.locSelectWorkspace))
                        .interfaceFont(size: 12, weight: .medium)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .interfaceFont(size: 8)
                }
                .foregroundColor(Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            .popover(isPresented: $showWorkspaceDropdown) {
                WorkspaceDropdown(isPresented: $showWorkspaceDropdown).environmentObject(appState)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var inputCore: some View {
        CompactChatPromptField(
            text: $messageText,
            placeholder: MiMoCopy.promptPlaceholder(language: appState.appLanguage),
            onSubmit: {
                hasAttemptedSend = true
                guard SendButtonActivationLogic.canInvokeSend(canSend: canSend, isLoading: isLoading) else { return }
                onSend()
            },
            focusRequest: appState.inputFocusRequest,
            maxHeightOverride: maxTextHeight
        )
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var pendingQueueSection: some View {
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
        .padding(.bottom, 4)
    }

    private var capsuleDivider: some View {
        Rectangle()
            .fill(Color.mimo.border.opacity(0.55))
            .frame(height: 1)
    }

    private var capsuleBackground: some View {
        RoundedRectangle(cornerRadius: InputCardLayoutLogic.capsuleCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.mimo.surface.opacity(0.96),
                        Color.mimo.surface.opacity(0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var capsuleStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.mimo.brand.opacity(0.45),
                Color.mimo.border.opacity(0.8),
                Color.mimo.cyan.opacity(0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
