import SwiftUI

/// Full-window spec wizard shown instead of the chat for projects created via
/// the sidebar's "Project setup" entry. The setup step captures the model
/// roles and the brief; the following steps run the planner interview, store
/// each specification revision, and split the approved spec into tasks.
/// Chat stays blocked until the decomposition exists or the user force-finishes.
struct SpecWizardView: View {
    @EnvironmentObject var appState: AppState

    let projectPath: String
    let projectName: String

    @State var session: SpecWizardSession?
    @State var initError: String?

    var body: some View {
        Group {
            if let session {
                SpecWizardContent(session: session)
                    .environmentObject(appState)
            } else if let initError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .interfaceFont(size: 22)
                        .foregroundColor(Color.mimo.error)
                    Text(initError)
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(L.t("Finish setup")) {
                        appState.finishSpecWizard(for: projectPath)
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .foregroundColor(Color.mimo.cyan)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.mimo.background)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.mimo.background)
            }
        }
        .onAppear(perform: makeSession)
    }

    private func makeSession() {
        guard session == nil else { return }
        do {
            let created = try SpecWizardSessionStore.shared.session(
                projectPath: projectPath,
                projectName: projectName,
                appState: appState
            )
            session = created
        } catch {
            initError = L.t("Could not open the project database.")
        }
    }
}

// MARK: - Content

struct SpecWizardContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var session: SpecWizardSession

    @State var answerText = ""
    @State var clarifyText = ""
    @State var specEditorText = ""
    @State var isEditingSpec = false
    @State var saveTask: Task<Void, Never>?
    @State var saveState: SaveState = .idle
    @State var showFinishConfirmation = false
    @State var showSettingsHint = false

    init(session: SpecWizardSession) {
        self.session = session
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed
    }

    var draft: SpecWizardDraft { session.draft }
    var modelGroups: [SpecModelGroup] {
        SpecWizardModelCatalog.groups(
            serverProviders: appState.serverProviders,
            customProviders: appState.customProviders,
            localProviders: LocalProviderLogic.load(defaults: appState.defaults),
            defaults: appState.defaults
        )
    }
    var checklist: [SpecWizardChecklistLogic.Item] {
        SpecWizardChecklistLogic.items(for: draft)
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                            .id("wizardTop")
                        if session.isLoading {
                            busyBanner
                        }
                        phaseContent
                        if let error = session.errorMessage {
                            errorBanner(error)
                        }
                        footer
                    }
                    .padding(28)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                // Jumping to another step must not leave the user in the
                // middle of a long task list.
                .onChange(of: visibleStep) { _ in
                    proxy.scrollTo("wizardTop", anchor: .top)
                }
            }

            Divider()

            checklistPane
                .frame(width: 300)
        }
        .background(Color.mimo.background)
        .onChange(of: session.draft) { _ in scheduleSave() }
        .onChange(of: session.draft.visibleStep) { step in
            if step == .interview {
                Task { await session.startInterviewIfNeeded() }
            }
        }
        .task {
            await session.startInterviewIfNeeded()
        }
        .alert(L.t("Finish setup and open chat?"), isPresented: $showFinishConfirmation) {
            Button(L.t("Cancel"), role: .cancel) {}
            Button(L.t("Finish setup"), role: .destructive) { forceFinish() }
        } message: {
            Text(L.t("Unfinished steps stay saved. You can come back later; chat will open now."))
        }
        .alert(L.t("No models configured"), isPresented: $showSettingsHint) {
            Button(L.t("Open settings")) {
                appState.showSettings = true
                appState.settingsTab = .providers
            }
            Button(L.t("Cancel"), role: .cancel) {}
        } message: {
            Text(L.t("Add a provider or connect a local model before choosing the planning and coding models."))
        }
    }

}
