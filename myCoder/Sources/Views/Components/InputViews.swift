import SwiftUI
import AppKit

struct AttachedFilesStrip: View {
    @Binding var attachedFiles: [FileInfo]
    @State private var hoveredFileID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if !attachedFiles.isEmpty {
                HStack {
                    Text(attachedFiles.count == 1 ? L.t(AppLocalizationKey.locFileAttached, attachedFiles.count) : L.t(AppLocalizationKey.locFilesAttached, attachedFiles.count))
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textMuted)
                    Spacer()
                    Button(action: { attachedFiles.removeAll() }) {
                        Text(L.t(AppLocalizationKey.locClearAll))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.brand)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedFiles) { file in
                            HStack(spacing: 6) {
                                Image(systemName: fileIcon(for: file))
                                    .interfaceFont(size: 12)
                                    .foregroundColor(Color.mimo.brand)

                                Text(file.name)
                                    .interfaceFont(size: 11)
                                    .foregroundColor(Color.mimo.textSecondary)
                                    .lineLimit(1)

                                if hoveredFileID == file.id, let path = file.path {
                                    Button(action: { revealInFinder(path) }) {
                                        Image(systemName: "folder")
                                            .interfaceFont(size: 10)
                                            .foregroundColor(Color.mimo.textMuted)
                                    }
                                    .buttonStyle(HandCursorButtonStyle())
                                    .help(L.t(AppLocalizationKey.locShowInFinder))
                                }

                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        attachedFiles.removeAll { $0.id == file.id }
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .interfaceFont(size: 12)
                                        .foregroundColor(Color.mimo.textMuted)
                                }
                                .buttonStyle(HandCursorButtonStyle())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.mimo.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(hoveredFileID == file.id ? Color.mimo.brand : Color.clear, lineWidth: 1)
                            )
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    hoveredFileID = hovering ? file.id : nil
                                }
                            }
                            .onTapGesture(count: 2) {
                                if let path = file.path {
                                    revealInFinder(path)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Divider()
            }
        }
        .background(attachedFiles.isEmpty ? Color.clear : Color.mimo.surface.opacity(0.5))
    }

    private func fileIcon(for file: FileInfo) -> String {
        switch file.type {
        case .swift, .python, .javascript, .typescript, .dart: return "chevron.left.forwardslash.chevron.right"
        case .json, .yaml: return "curlybraces"
        case .markdown: return "doc.richtext"
        case .html, .css: return "globe"
        case .unknown:
            let ext = (file.name as NSString).pathExtension.lowercased()
            if ClipboardPasteLogic.imageExtensions.contains(ext) { return "photo" }
            if ext == "pdf" { return "doc.fill" }
            return "doc"
        }
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

struct ImagePreviewStrip: View {
    @Binding var attachedImages: [ClipboardImage]
    @State private var hoveredImageID: UUID?
    @State private var previewImage: ClipboardImage?
    
    var body: some View {
        VStack(spacing: 0) {
            if !attachedImages.isEmpty {
                HStack {
                    Text(attachedImages.count == 1 ? L.t(AppLocalizationKey.locPhotoAttached, attachedImages.count) : L.t(AppLocalizationKey.locPhotosAttached, attachedImages.count))
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textMuted)
                    Spacer()
                    Button(action: { attachedImages.removeAll() }) {
                        Text(L.t(AppLocalizationKey.locClearAll))
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.brand)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedImages) { img in
                            if let data = Data(base64Encoded: img.base64),
                               let nsImage = NSImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(hoveredImageID == img.id ? Color.mimo.brand : Color.clear, lineWidth: 2)
                                        )
                                        .onHover { hovering in
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                hoveredImageID = hovering ? img.id : nil
                                            }
                                        }
                                        .onTapGesture {
                                            previewImage = img
                                        }
                                    
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            attachedImages.removeAll { $0.id == img.id }
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .interfaceFont(size: 14)
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.5), radius: 2)
                                    }
                                    .buttonStyle(HandCursorButtonStyle())
                                    .offset(x: 6, y: -6)
                                    .opacity(hoveredImageID == img.id ? 1 : 0.7)
                                }
                                .frame(width: 80, height: 80)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Divider()
            }
        }
        .background(attachedImages.isEmpty ? Color.clear : Color.mimo.surface.opacity(0.5))
        .sheet(item: $previewImage) { img in
            ImagePreviewSheet(image: img, attachedImages: $attachedImages, onDismiss: { previewImage = nil })
        }
    }
}

struct ImagePreviewSheet: View {
    let image: ClipboardImage
    @Binding var attachedImages: [ClipboardImage]
    let onDismiss: () -> Void
    
    var body: some View {
        if let data = Data(base64Encoded: image.base64),
           let nsImage = NSImage(data: data) {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Text(L.t(AppLocalizationKey.locImagePreview))
                        .interfaceFont(size: 14, weight: .medium)
                        .foregroundColor(Color.mimo.textPrimary)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .interfaceFont(size: 18)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 600, maxHeight: 500)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                
                HStack(spacing: 12) {
                    Button(action: {
                        if let idx = attachedImages.firstIndex(where: { $0.id == image.id }) {
                            attachedImages.remove(at: idx)
                        }
                        onDismiss()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .interfaceFont(size: 12)
                            Text(L.t(AppLocalizationKey.locRemove))
                                .interfaceFont(size: 12)
                        }
                        .foregroundColor(.red)
                .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    
                    Button(action: onDismiss) {
                        Text(L.t(AppLocalizationKey.locKeep))
                            .interfaceFont(size: 12, weight: .medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(Color.mimo.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(HandCursorButtonStyle())
                }
                .padding(.bottom, 16)
            }
            .frame(width: 640, height: 600)
            .background(Color.mimo.background)
        } else {
            VStack {
                Text(L.t(AppLocalizationKey.locCannotPreviewImage))
                    .foregroundColor(Color.mimo.textMuted)
                Button(L.t(AppLocalizationKey.locClose)) { onDismiss() }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.brand)
            }
            .frame(width: 300, height: 200)
            .background(Color.mimo.background)
        }
    }
}

struct CompactChatPromptField: View {
    @Binding var text: String
    let placeholder: String
    var onSubmit: () -> Void
    var focusRequest: Int = 0
    var maxHeightOverride: CGFloat? = nil

    var body: some View {
        CompactMessageTextField(
            text: $text,
            placeholder: placeholder,
            onSubmit: onSubmit,
            compactSingleLine: true,
            focusRequest: focusRequest,
            maxHeightOverride: maxHeightOverride
        )
    }
}

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
            autoFreeReady: MyCoderAutoFreeStore.shared.provider.isReady,
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
            autoFreeReady: MyCoderAutoFreeStore.shared.provider.isReady,
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
            autoFreeReady: MyCoderAutoFreeStore.shared.provider.isReady,
            customProviders: appState.customProviders,
            localProviderIDs: appState.localProviderIDs,
            webProviderIDs: appState.webProviderIDs,
            serverProviderIDs: appState.serverProviders.map(\.id),
            webConnected: WebProviderConnectivity.configID(fromOptionID: appState.selectedProviderID) == nil
                ? nil
                : appState.selectedProviderConnected
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
            autoFreeReady: MyCoderAutoFreeStore.shared.provider.isReady,
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

            CompactMessageTextField(
                text: $messageText,
                placeholder: MiMoCopy.followUpPlaceholder(language: appState.appLanguage),
                onSubmit: {
                    guard SendButtonActivationLogic.canInvokeSend(canSend: canSend, isLoading: isLoading) else { return }
                    onSend()
                },
                compactSingleLine: messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                focusRequest: appState.inputFocusRequest
            )
            .padding(.vertical, 4)
            // Context ring lives in the top-right corner of the input card and
            // never occupies its own line (user directive 2026-10-24).
            .overlay(alignment: .topTrailing) {
                if let contextUsage {
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
                canSend: canSend,
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

struct WorkspaceDropdown: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var searchText = ""
    
    var filteredWorkspaces: [Workspace] {
        if searchText.isEmpty { return appState.workspaces }
        return appState.workspaces.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").interfaceFont(size: 12).foregroundColor(Color.mimo.textMuted)
                TextField(L.t(AppLocalizationKey.locSearchWorkspaces), text: $searchText).textFieldStyle(.plain).interfaceFont(size: 13)
            }.padding(8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredWorkspaces) { workspace in
                        Button(action: { appState.selectWorkspace(workspace); isPresented = false }) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder").interfaceFont(size: 12).foregroundColor(Color.mimo.textMuted)
                                Text(workspace.name).interfaceFont(size: 13).foregroundColor(Color.mimo.textPrimary)
                                Spacer()
                                if appState.selectedWorkspace?.id == workspace.id {
                                    Image(systemName: "checkmark").interfaceFont(size: 12).foregroundColor(Color.mimo.brand)
                                }
                            }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(HandCursorButtonStyle())
                    }
                    Divider().padding(.vertical, 4)
                    Button(action: { openFolder() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus").interfaceFont(size: 12).foregroundColor(Color.mimo.textMuted)
                            Text(L.t(AppLocalizationKey.locOpenFolder)).interfaceFont(size: 13).foregroundColor(Color.mimo.textPrimary)
                        }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(HandCursorButtonStyle())
                    Button(action: { isPresented = false; appState.showRemoteConnection = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "cloud").interfaceFont(size: 12).foregroundColor(Color.mimo.textMuted)
                            Text(L.t(AppLocalizationKey.locRemoteConnection)).interfaceFont(size: 13).foregroundColor(Color.mimo.textPrimary)
                        }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(HandCursorButtonStyle())
                }
            }
        }.frame(width: 280, height: 320)
        .background(Color.mimo.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
    
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            appState.addWorkspace(path: url.path)
            isPresented = false
        }
    }
}

// MARK: - Pending Message Card

struct PendingMessageCard: View {
    let queued: QueuedMessage
    let index: Int
    let onForceSend: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Agent mode icon
            Image(systemName: queued.type.icon)
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.brand)
                .frame(width: 14)
            
            // Text preview
            Text(queued.text)
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Attachments preview (images + files)
            if !queued.images.isEmpty || !queued.files.isEmpty {
                HStack(spacing: 2) {
                    // Image thumbnails (max 3)
                    ForEach(queued.images.prefix(3), id: \.base64) { img in
                        if let data = Data(base64Encoded: img.base64),
                           let nsImage = NSImage(data: data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .frame(width: 18, height: 18)
                                .cornerRadius(3)
                        }
                    }
                    // File icons (max 2)
                    ForEach(queued.files.prefix(2)) { file in
                        HStack(spacing: 2) {
                            Image(systemName: "doc.text")
                                .interfaceFont(size: 9)
                            Text(file.name)
                                .interfaceFont(size: 9)
                                .lineLimit(1)
                        }
                        .foregroundColor(Color.mimo.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.mimo.textMuted.opacity(0.1))
                        .cornerRadius(3)
                    }
                    
                    // Overflow count
                    let imageCount = min(queued.images.count, 3)
                    let fileCount = min(queued.files.count, 2)
                    let shown = imageCount + fileCount
                    let total = queued.images.count + queued.files.count
                    if total > shown {
                        Text("+\(total - shown)")
                            .interfaceFont(size: 9, weight: .medium)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                }
            }
            
            // Queue position
            Text("#\(index + 1)")
                .interfaceFont(size: 10, weight: .medium)
                .foregroundColor(Color.mimo.textMuted)
            
            // Force-send now (interrupts the current turn).
            Button(action: onForceSend) {
                Image(systemName: "paperplane.fill")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.brand)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locSendNow))

            // Edit the queued message in the composer (draft is preserved).
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locEditQueuedMessage))

            // Cancel/remove this queued message.
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
            }
            .buttonStyle(HandCursorButtonStyle())
            .help(L.t(AppLocalizationKey.locDeleteQueuedMessage))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.mimo.brand.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
