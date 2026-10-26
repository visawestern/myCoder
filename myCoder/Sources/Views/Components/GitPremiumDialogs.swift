import SwiftUI

// MARK: - Premium chrome

/// Shared premium dialog chrome: gradient icon badge, gradient hairline
/// border, title/subtitle header and an action row.
struct PremiumDialogChrome<Content: View, Actions: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [Color.mimo.brand, Color.mimo.violet, Color.mimo.cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(brandGradient)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .interfaceFont(size: 18, weight: .semibold)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .interfaceFont(size: 16, weight: .semibold)
                        .foregroundColor(Color.mimo.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            content

            HStack(spacing: 8) {
                Spacer()
                actions
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Color.mimo.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(brandGradient.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct PremiumPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isBusy = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .interfaceFont(size: 12, weight: .semibold)
                }
                Text(title)
                    .interfaceFont(size: 12, weight: .semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: isEnabled
                        ? [Color.mimo.brand, Color.mimo.violet]
                        : [Color.mimo.textMuted, Color.mimo.textMuted],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(HandCursorButtonStyle())
        .disabled(!isEnabled || isBusy)
    }
}

struct PremiumSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .interfaceFont(size: 12, weight: .medium)
                .foregroundColor(Color.mimo.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.mimo.backgroundAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mimo.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(HandCursorButtonStyle())
        .keyboardShortcut(.cancelAction)
    }
}

// MARK: - Init dialog

struct GitInitDialogView: View {
    let language: AppLanguage
    @Binding var isPresented: Bool
    var onInitialize: () -> Void

    var body: some View {
        PremiumDialogChrome(
            icon: "folder.badge.plus",
            title: AppLocalization.string(.gitInitTitle, language: language),
            subtitle: AppLocalization.string(.gitInitSubtitle, language: language)
        ) {
            EmptyView()
        } actions: {
            PremiumSecondaryButton(title: AppLocalization.string(.gitCancel, language: language)) {
                isPresented = false
            }
            PremiumPrimaryButton(
                title: AppLocalization.string(.gitInitialize, language: language),
                systemImage: "plus.circle.fill"
            ) {
                onInitialize()
                isPresented = false
            }
        }
    }
}

// MARK: - Publish wizard

struct GitHubPublishWizardView: View {
    let language: AppLanguage
    let workspaceName: String
    @Binding var isPresented: Bool
    /// Called with (ghPath, repoName, isPublic) once the user confirms publishing.
    var onPublish: (String, String, Bool) -> Void

    @State private var step: GitPublishStep?
    @State private var ghPath: String?
    @State private var repoName = ""
    @State private var isPublic = false
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var signInCode: String?

    var body: some View {
        PremiumDialogChrome(
            icon: stepIcon,
            title: stepTitle,
            subtitle: stepSubtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                switch step {
                case nil:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("…")
                            .interfaceFont(size: 12)
                            .foregroundColor(Color.mimo.textMuted)
                    }
                case .installCLI:
                    Link(
                        AppLocalization.string(.gitOpenGitHubDocs, language: language),
                        destination: GitPublishFlowLogic.manualInstallURL
                    )
                    .interfaceFont(size: 11)
                case .signIn:
                    if let signInCode {
                        HStack(spacing: 8) {
                            Text(signInCode)
                                .interfaceFont(size: 20, weight: .bold, design: .monospaced)
                                .foregroundColor(Color.mimo.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.mimo.backgroundAlt)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Spacer(minLength: 0)
                        }
                    }
                case .publishForm:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string(.gitRepoName, language: language))
                            .interfaceFont(size: 11, weight: .medium)
                            .foregroundColor(Color.mimo.textSecondary)
                        TextField(
                            AppLocalization.string(.gitRepoName, language: language),
                            text: $repoName
                        )
                        .textFieldStyle(.roundedBorder)

                        Picker(AppLocalization.string(.gitVisibility, language: language), selection: $isPublic) {
                            Text(AppLocalization.string(.gitPrivate, language: language)).tag(false)
                            Text(AppLocalization.string(.gitPublic, language: language)).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }
        } actions: {
            PremiumSecondaryButton(title: AppLocalization.string(.gitCancel, language: language)) {
                isPresented = false
            }

            switch step {
            case nil:
                EmptyView()
            case .installCLI:
                PremiumPrimaryButton(
                    title: AppLocalization.string(.gitInstallGHButton, language: language),
                    systemImage: "shippingbox.fill",
                    isBusy: isBusy
                ) {
                    runInstall()
                }
            case .signIn:
                PremiumPrimaryButton(
                    title: AppLocalization.string(.gitSignInButton, language: language),
                    systemImage: "person.badge.key.fill",
                    isBusy: isBusy
                ) {
                    runSignIn()
                }
            case .publishForm:
                PremiumPrimaryButton(
                    title: AppLocalization.string(.gitCreateAndPush, language: language),
                    systemImage: "arrow.up.circle.fill",
                    isBusy: isBusy,
                    isEnabled: GitPublishFlowLogic.isValidRepoName(repoName)
                ) {
                    guard let ghPath else { return }
                    onPublish(ghPath, repoName.trimmingCharacters(in: .whitespacesAndNewlines), isPublic)
                    isPresented = false
                }
            }
        }
        .task {
            repoName = GitPublishFlowLogic.suggestedRepoName(from: workspaceName)
            await detect()
        }
    }

    private var stepIcon: String {
        switch step {
        case .installCLI: return "shippingbox"
        case .signIn: return "person.crop.circle.badge.checkmark"
        default: return "arrow.up.forward.app"
        }
    }

    private var stepTitle: String {
        switch step {
        case .installCLI: return AppLocalization.string(.gitInstallGHTitle, language: language)
        case .signIn: return AppLocalization.string(.gitSignInTitle, language: language)
        default: return AppLocalization.string(.gitPublishTitle, language: language)
        }
    }

    private var stepSubtitle: String? {
        switch step {
        case .installCLI: return AppLocalization.string(.gitInstallGHSubtitle, language: language)
        case .signIn: return AppLocalization.string(.gitSignInSubtitle, language: language)
        case .publishForm: return nil
        case nil: return nil
        }
    }

    private func detect() async {
        let result = await GitHubCLIService.detect()
        ghPath = result.ghPath
        step = GitPublishFlowLogic.step(for: result.status)
    }

    private func runInstall() {
        isBusy = true
        errorText = nil
        Task {
            do {
                try await GitHubCLIService.installViaHomebrew()
                await detect()
            } catch {
                errorText = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func runSignIn() {
        guard let ghPath else { return }
        isBusy = true
        errorText = nil
        signInCode = nil
        Task {
            do {
                try await GitHubCLIService.signIn(ghPath: ghPath) { code in
                    signInCode = code
                }
                await detect()
            } catch {
                errorText = error.localizedDescription
            }
            signInCode = nil
            isBusy = false
        }
    }
}

// MARK: - Review & push dialog

struct ReviewPushDialogView: View {
    let language: AppLanguage
    /// Auto-generated summary of pending changes, shown and appended to the commit message.
    let autoSummary: String
    @Binding var isPresented: Bool
    var onCommitAndPush: (String) -> Void

    @State private var comment = ""

    var body: some View {
        PremiumDialogChrome(
            icon: "checkmark.seal.fill",
            title: AppLocalization.string(.gitReviewPush, language: language),
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.string(.gitReviewComment, language: language))
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textSecondary)
                    TextField(
                        AppLocalization.string(.gitReviewCommentPlaceholder, language: language),
                        text: $comment,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                }

                if !autoSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string(.gitReviewSummary, language: language))
                            .interfaceFont(size: 11, weight: .medium)
                            .foregroundColor(Color.mimo.textSecondary)
                        Text(autoSummary)
                            .interfaceFont(size: 11, design: .monospaced)
                            .foregroundColor(Color.mimo.textMuted)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.mimo.backgroundAlt)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } actions: {
            PremiumSecondaryButton(title: AppLocalization.string(.gitCancel, language: language)) {
                isPresented = false
            }
            PremiumPrimaryButton(
                title: AppLocalization.string(.gitCommitAndPush, language: language),
                systemImage: "arrow.up.circle.fill"
            ) {
                onCommitAndPush(comment)
                isPresented = false
            }
        }
    }
}

// MARK: - Pull request dialog

/// Creates a real pull request for the current branch via `gh pr create`
/// (Раздел 5 п.16 — `/pr` must perform a real action, not send text).
struct PullRequestDialogView: View {
    let language: AppLanguage
    let workspacePath: String
    @Binding var isPresented: Bool
    /// Called with (title, body) once the user confirms.
    var onCreate: (String, String) -> Void

    @State private var title = ""
    @State private var prBody = ""
    @State private var ghPath: String?
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var checkedStatus = false

    var body: some View {
        PremiumDialogChrome(
            icon: "arrow.branch",
            title: L.t(AppLocalizationKey.locCreatePullRequest),
            subtitle: ghPath == nil && checkedStatus ? nil : nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t(AppLocalizationKey.locTitle))
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textSecondary)
                    TextField(L.t(AppLocalizationKey.locShortSummary), text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t(AppLocalizationKey.locDescriptionOptional))
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.textSecondary)
                    TextField(L.t(AppLocalizationKey.locWhatChanged), text: $prBody, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(.roundedBorder)
                }
            }
        } actions: {
            PremiumSecondaryButton(title: AppLocalization.string(.gitCancel, language: language)) {
                isPresented = false
            }
            PremiumPrimaryButton(
                title: L.t(AppLocalizationKey.locCreate),
                systemImage: "arrow.branch",
                isBusy: isBusy,
                isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ghPath != nil
            ) {
                onCreate(
                    title.trimmingCharacters(in: .whitespacesAndNewlines),
                    prBody.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                isPresented = false
            }
        }
        .task {
            title = "\((workspacePath as NSString).lastPathComponent) changes"
            let result = await GitHubCLIService.detect()
            ghPath = result.ghPath
            checkedStatus = true
            if ghPath == nil {
                errorText = L.t(AppLocalizationKey.locGitHubCliNotInstalled)
            }
        }
    }
}

// MARK: - Commit dialog

struct CommitDialogView: View {
    let language: AppLanguage
    /// Auto-generated summary used when the user picks the auto option.
    let autoSummary: String
    @Binding var isPresented: Bool
    var onCommit: (String) -> Void

    @State private var useCustomMessage = false
    @State private var customMessage = ""

    private var resolvedMessage: String {
        if useCustomMessage {
            return customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return autoSummary.isEmpty ? CommitMessageComposer.fallbackMessage : autoSummary
    }

    var body: some View {
        PremiumDialogChrome(
            icon: "arrow.up.to.line.circle.fill",
            title: AppLocalization.string(.gitCommit, language: language),
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $useCustomMessage) {
                    Text(AppLocalization.string(.gitCommitAuto, language: language)).tag(false)
                    Text(AppLocalization.string(.gitCommitCustom, language: language)).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if useCustomMessage {
                    TextField(
                        AppLocalization.string(.gitCommitCustom, language: language),
                        text: $customMessage,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                } else if !autoSummary.isEmpty {
                    Text(autoSummary)
                        .interfaceFont(size: 11, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.mimo.backgroundAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } actions: {
            PremiumSecondaryButton(title: AppLocalization.string(.gitCancel, language: language)) {
                isPresented = false
            }
            PremiumPrimaryButton(
                title: AppLocalization.string(.gitCommit, language: language),
                systemImage: "checkmark.circle.fill",
                isEnabled: !resolvedMessage.isEmpty
            ) {
                onCommit(resolvedMessage)
                isPresented = false
            }
        }
    }
}
