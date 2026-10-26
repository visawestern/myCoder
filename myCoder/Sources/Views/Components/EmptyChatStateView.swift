import SwiftUI

struct EmptyChatStateView: View {
    @EnvironmentObject var appState: AppState
    @Binding var messageText: String
    @ObservedObject var attachmentStore: MessageAttachmentStore
    @Binding var showFilePicker: Bool
    @ObservedObject var messageQueue: MessageQueue
    let onSend: () -> Void
    let onStop: () -> Void
    let isLoading: Bool
    let isLoadingChat: Bool

    var body: some View {
        GeometryReader { geometry in
            let maxTextHeight = geometry.size.height * 0.8

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: ChatPanelLayoutLogic.emptyStateStackSpacing) {
                    if isLoadingChat {
                        ProgressView()
                            .controlSize(.regular)
                            .scaleEffect(1.15)
                        Text(L.t(AppLocalizationKey.locLoadingChat))
                            .interfaceFont(size: 14, weight: .medium)
                            .foregroundColor(Color.mimo.textMuted)
                            .multilineTextAlignment(.center)
                    } else {
                        MiMoLogoMark(size: 140)

                        if let session = appState.selectedSession {
                            Text(session.title)
                                .interfaceFont(size: 22, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                                .multilineTextAlignment(.center)
                        } else if let workspace = appState.selectedWorkspace {
                            Text(MiMoCopy.emptyStateTitle(workspaceName: workspace.name, language: appState.appLanguage))
                                .interfaceFont(size: 22, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text(MiMoCopy.emptyStateSelectWorkspace(language: appState.appLanguage))
                                .interfaceFont(size: 22, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    CenteredInputCard(
                        messageText: $messageText,
                        onSend: onSend,
                        onStop: onStop,
                        isLoading: isLoading,
                        attachmentStore: attachmentStore,
                        showFilePicker: $showFilePicker,
                        messageQueue: messageQueue,
                        requestInputFocus: true,
                        autoGrow: true,
                        maxTextHeight: maxTextHeight
                    )
                    .frame(maxWidth: InputLayout.cardMaxWidth)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
