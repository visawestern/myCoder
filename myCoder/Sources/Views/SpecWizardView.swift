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

    @State private var session: SpecWizardSession?
    @State private var initError: String?

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

private struct SpecWizardContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var session: SpecWizardSession
    @ObservedObject private var autoFreeStore = MyCoderAutoFreeStore.shared

    @State private var answerText = ""
    @State private var clarifyText = ""
    @State private var specEditorText = ""
    @State private var isEditingSpec = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saveState: SaveState = .idle
    @State private var showFinishConfirmation = false
    @State private var showSettingsHint = false

    init(session: SpecWizardSession) {
        self.session = session
    }

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed
    }

    private var draft: SpecWizardDraft { session.draft }
    private var modelGroups: [SpecModelGroup] {
        SpecWizardModelCatalog.groups(
            serverProviders: appState.serverProviders,
            customProviders: appState.customProviders,
            localProviders: LocalProviderLogic.load(defaults: appState.defaults),
            autoFree: autoFreeStore.provider,
            defaults: appState.defaults
        )
    }
    private var checklist: [SpecWizardChecklistLogic.Item] {
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

    // MARK: Header

    private var visibleStep: SpecWizardStep {
        let furthest = draft.furthestStep
        guard let active = draft.activeStep, active.rank <= furthest.rank else { return furthest }
        guard draft.status != .draft else { return active }
        // A finished project opens on its task board, but an explicit return
        // to an earlier phase is still honored.
        if active.rank < SpecWizardStep.ready.rank { return active }
        return session.nodes.isEmpty ? .ready : .decomposition
    }

    private var stepNumber: Int {
        switch visibleStep {
        case .setup: return 1
        case .interview: return 2
        case .specification: return 3
        case .decomposition: return 4
        case .ready: return 4
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .interfaceFont(size: 22, weight: .medium)
                    .foregroundColor(Color.mimo.cyan)
                    .padding(10)
                    .background(Color.mimo.cyan.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L.t("Project setup"))
                            .interfaceFont(size: 20, weight: .semibold)
                            .foregroundColor(Color.mimo.textPrimary)
                        Text(L.t(phaseTitle))
                            .interfaceFont(size: 10, weight: .semibold)
                            .foregroundColor(Color.mimo.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.mimo.cyan.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    Text(session.projectName)
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(stepNumber) / 4")
                    .interfaceFont(size: 10, weight: .bold, design: .monospaced)
                    .foregroundColor(Color.mimo.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.mimo.cyan.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.mimo.cyan.opacity(0.35), lineWidth: 1))
            }

            Text(L.t(phaseSubtitle))
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var phaseTitle: String {
        switch visibleStep {
        case .setup: return "Setup"
        case .interview: return "Questions"
        case .specification: return "Specification"
        case .decomposition: return "Tasks"
        case .ready: return "Ready"
        }
    }

    private var phaseSubtitle: String {
        switch visibleStep {
        case .setup:
            return "Describe the project. The questions, checklist and task breakdown build on this setup."
        case .interview:
            return "The model asks one question at a time. Every question and answer is saved with the project."
        case .specification:
            return "Your answers become a versioned specification. Edit it before breaking the work into tasks if needed."
        case .decomposition:
            return "The specification is split into tasks with dependencies and clear completion criteria."
        case .ready:
            return "The specification and task breakdown are ready. Finish setup to open chat."
        }
    }

    // MARK: Phases

    @ViewBuilder
    private var phaseContent: some View {
        switch visibleStep {
        case .setup:
            setupPhase
        case .interview:
            interviewPhase
        case .specification:
            specificationPhase
        case .decomposition:
            decompositionPhase
        case .ready:
            readyPhase
        }
    }

    private var setupPhase: some View {
        VStack(spacing: 20) {
            modelsCard
            briefCard
            HStack {
                Spacer()
                primaryButton(L.t("Continue to questions"), icon: "arrow.right", isBusy: session.isLoading) {
                    guard draft.hasModels else {
                        session.errorMessage = L.t("Choose both models")
                        return
                    }
                    guard draft.hasBrief else {
                        session.errorMessage = L.t("Goal and technologies are required")
                        return
                    }
                    guard session.go(to: .interview) else { return }
                    Task { await session.startInterviewIfNeeded() }
                }
                .disabled(!draft.hasModels || !draft.hasBrief || session.isLoading)
            }
        }
    }

    private var modelsCard: some View {
        card(title: L.t("Project models"), icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                SpecModelPicker(
                    title: L.t("Planning model"),
                    hint: L.t("Asks questions and writes the specification and task breakdown."),
                    groups: modelGroups,
                    providerID: $session.draft.plannerProviderID,
                    modelID: $session.draft.plannerModel,
                    onManageModels: openModelSettings
                )
                Divider().opacity(0.5)
                SpecModelPicker(
                    title: L.t("Coding model"),
                    hint: L.t("Implements one task at a time using the specification."),
                    groups: modelGroups,
                    providerID: $session.draft.coderProviderID,
                    modelID: $session.draft.coderModel,
                    onManageModels: openModelSettings
                )

                if modelGroups.isEmpty {
                    Button(L.t("Configure models…")) { showSettingsHint = true }
                        .buttonStyle(HandCursorButtonStyle())
                        .interfaceFont(size: 11, weight: .medium)
                        .foregroundColor(Color.mimo.cyan)
                }
            }
        }
    }

    private func openModelSettings() {
        appState.showSettings = true
        appState.settingsTab = .providers
    }

    private var briefCard: some View {
        card(title: L.t("Project description"), icon: "doc.text") {
            VStack(alignment: .leading, spacing: 14) {
                briefField(
                    title: L.t("Goal"),
                    placeholder: L.t("What should this project do, and for whom?"),
                    text: $session.draft.goal,
                    height: 88
                )
                briefField(
                    title: L.t("Technologies"),
                    placeholder: L.t("Languages, frameworks, storage, target platform…"),
                    text: $session.draft.stack,
                    height: 64
                )
                briefField(
                    title: L.t("Constraints"),
                    placeholder: L.t("Deadlines, compatibility, security, things that must not change…"),
                    text: $session.draft.constraints,
                    height: 64
                )
            }
        }
    }

    private func briefField(title: String, placeholder: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .interfaceFont(size: 11, weight: .semibold)
                .foregroundColor(Color.mimo.textSecondary)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(.system(size: 12))
                    .foregroundColor(Color.mimo.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(4)
            }
            .frame(height: height)
            .background(Color.mimo.controlBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.mimo.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Questions

    /// One visible progress line for every long step (interview, summary,
    /// specification, decomposition), so the wizard never looks frozen.
    private var busyBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L.t("Working…"))
                .interfaceFont(size: 11, weight: .medium)
                .foregroundColor(Color.mimo.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.mimo.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var interviewPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(SpecWizardInterviewLayoutLogic.blocks(
                hasQuestion: session.currentQuestion != nil,
                isQuestionCardVisible: session.isQuestionCardVisible,
                hasCompletedSummary: session.completedSummary != nil,
                interviewComplete: draft.interviewComplete
            ), id: \.self) { block in
                switch block {
                case .question:
                    if let question = session.currentQuestion, !question.done {
                        questionCard(question)
                    }
                case .summary:
                    if let summary = session.completedSummary {
                        completionCard(summary)
                    }
                case .feed:
                    feedCard
                }
            }
        }
    }

    /// The transcript of answered exchanges. It follows the live question and
    /// lists the newest exchange first (user directive 2026-10-28), so the
    /// question the user just answered is directly under the answer card
    /// instead of at the bottom of a long growing list.
    private var feedCard: some View {
        card(title: L.t("Project questions"), icon: "bubble.left.and.bubble.right") {
            VStack(alignment: .leading, spacing: 12) {
                if session.turns.isEmpty {
                    // A spinner that can never resolve looks like a frozen app
                    // (the exact bug from the 2026-10-27 screenshot). Show the
                    // progress only while a request is really in flight, and
                    // an honest retry otherwise.
                    if session.isLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L.t("Preparing the first question…"))
                                .interfaceFont(size: 12)
                                .foregroundColor(Color.mimo.textMuted)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L.t("The interview did not start. Check the planning model and try again."))
                                .interfaceFont(size: 12)
                                .foregroundColor(Color.mimo.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            secondaryButton(L.t("Retry"), icon: "arrow.clockwise") {
                                Task { await session.startInterviewIfNeeded() }
                            }
                        }
                    }
                } else {
                    if session.isLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L.t("The model is thinking…"))
                                .interfaceFont(size: 12)
                                .foregroundColor(Color.mimo.textMuted)
                        }
                    }
                    ForEach(Array(feedTurns.enumerated()), id: \.offset) { _, turn in
                        interviewTurn(turn)
                    }
                }
            }
        }
    }

    /// Answered turns, newest exchange first. The live question is owned by
    /// `questionCard` above, so it is excluded from the transcript.
    private var feedTurns: [SpecPlannerTurn] {
        let history = SpecWizardInterviewLayoutLogic.history(
            session.turns,
            excludingLiveQuestion: session.isQuestionCardVisible && session.currentQuestion != nil
        )
        return SpecWizardInterviewLayoutLogic.newestFirst(history)
    }

    /// What the planner understood, with a way to correct it before the
    /// specification is written.
    private func completionCard(_ summary: String) -> some View {
        card(title: L.t("Questions complete"), icon: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 12) {
                Text(summary)
                    .interfaceFont(size: 13)
                    .foregroundColor(Color.mimo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L.t("This is what I understood must be built. If something is missing or wrong, tell me what to clarify."))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TextField(L.t("What should be clarified?"), text: $clarifyText)
                        .textFieldStyle(.plain)
                        .interfaceFont(size: 12)
                        .padding(8)
                        .background(Color.mimo.controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.mimo.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .onSubmit { submitClarification() }

                    primaryButton(
                        L.t("Clarify"),
                        icon: "questionmark.bubble",
                        isBusy: session.isLoading && !clarifyText.isEmpty
                    ) {
                        submitClarification()
                    }
                    .disabled(session.isLoading || clarifyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Spacer()
                    if draft.specVersion > 0 {
                        // The spec already exists — never offer a silent
                        // regeneration here; the tasks screen owns that action.
                        primaryButton(L.t("Continue to tasks"), icon: "arrow.right") {
                            session.go(to: .decomposition)
                        }
                        .disabled(session.isLoading)
                    } else {
                        primaryButton(
                            L.t("Create specification"),
                            icon: "doc.badge.plus",
                            isBusy: session.isLoading
                        ) {
                            Task { await session.generateSpecification() }
                        }
                        .disabled(session.isLoading)
                    }
                }
            }
        }
    }

    private func interviewTurn(_ turn: SpecPlannerTurn) -> some View {
        let isPlanner = turn.role == "planner"
        let text = isPlanner ? plannerDisplayText(turn.content) : turn.content
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: isPlanner ? "wand.and.stars" : "person.fill")
                .interfaceFont(size: 10)
                .foregroundColor(isPlanner ? Color.mimo.cyan : Color.mimo.textMuted)
                .frame(width: 16)
            Text(text)
                .interfaceFont(size: 12)
                .foregroundColor(Color.mimo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(isPlanner ? Color.mimo.cyan.opacity(0.06) : Color.mimo.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func plannerDisplayText(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let question = try? JSONDecoder().decode(SpecInterviewQuestion.self, from: data) else {
            return raw
        }
        if question.done {
            return question.summary ?? L.t("Questions complete")
        }
        return question.question
    }

    private func questionCard(_ question: SpecInterviewQuestion) -> some View {
        card(title: L.t("Question"), icon: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Text(question.question)
                    .interfaceFont(size: 13, weight: .medium)
                    .foregroundColor(Color.mimo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !question.suggestedAnswers.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(question.suggestedAnswers, id: \.self) { answer in
                            Button {
                                submit(answer)
                            } label: {
                                Text(answer)
                                    .interfaceFont(size: 11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.mimo.controlBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(Color.mimo.border, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(HandCursorButtonStyle())
                            .foregroundColor(Color.mimo.textPrimary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(L.t("Your answer…"), text: $answerText)
                        .textFieldStyle(.plain)
                        .interfaceFont(size: 12)
                        .padding(8)
                        .background(Color.mimo.controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.mimo.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .onSubmit { submit(answerText) }

                    primaryButton(L.t("Send"), icon: "arrow.up") {
                        submit(answerText)
                    }
                    .disabled(session.isLoading || answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func submit(_ answer: String) {
        let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        answerText = ""
        Task {
            let ok = await session.submitAnswer(clean)
            // A failed turn stores nothing — put the text back so the user can
            // retry without retyping the answer. A double-send race (the
            // session is still busy, no error) must not resurrect it.
            if !ok, session.errorMessage != nil, answerText.isEmpty { answerText = clean }
        }
    }

    /// Sends the user's correction for the collected summary and lets the
    /// planner decide whether the task is clear enough now.
    private func submitClarification() {
        let clean = clarifyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        clarifyText = ""
        Task {
            let ok = await session.clarify(clean)
            if !ok, session.errorMessage != nil, clarifyText.isEmpty { clarifyText = clean }
        }
    }

    // MARK: Specification

    @ViewBuilder
    private var specificationPhase: some View {
        if draft.specVersion > 0 {
            VStack(alignment: .leading, spacing: 14) {
                specificationCard
                HStack {
                    Spacer()
                    primaryButton(L.t("Continue to tasks"), icon: "arrow.right") {
                        session.go(to: .decomposition)
                    }
                    .disabled(session.isLoading)
                }
            }
        } else {
            card(title: L.t("Technical specification"), icon: "doc.richtext") {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L.t("The model will write a versioned specification from your answers."))
                        .interfaceFont(size: 12)
                        .foregroundColor(Color.mimo.textSecondary)
                    HStack {
                        Spacer()
                        primaryButton(
                            L.t("Create specification"),
                            icon: "doc.badge.plus",
                            isBusy: session.isLoading
                        ) {
                            Task { await session.generateSpecification() }
                        }
                        .disabled(session.isLoading)
                    }
                }
            }
        }
    }

    private var specificationCard: some View {
        card(title: L.t("Technical specification"), icon: "doc.richtext") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("v\(draft.specVersion)")
                        .interfaceFont(size: 10, weight: .bold, design: .monospaced)
                        .foregroundColor(Color.mimo.cyan)
                    Spacer()
                    Button(L.t("Edit")) {
                        specEditorText = session.specification
                        isEditingSpec = true
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.cyan)
                }

                if isEditingSpec {
                    TextEditor(text: $specEditorText)
                        .font(.system(size: 12))
                        .foregroundColor(Color.mimo.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 260)
                        .background(Color.mimo.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button(L.t("Cancel")) {
                            isEditingSpec = false
                        }
                        .buttonStyle(HandCursorButtonStyle())
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textMuted)
                        Spacer()
                        primaryButton(L.t("Save as new version"), icon: "square.and.arrow.down") {
                            session.saveSpecificationEdits(specEditorText)
                            isEditingSpec = false
                        }
                    }
                } else {
                    MarkdownText(text: session.specification, fontSize: 12)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.mimo.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 10) {
                    Button(L.t("Regenerate")) {
                        Task { await session.generateSpecification() }
                    }
                    .buttonStyle(HandCursorButtonStyle())
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                    .disabled(session.isLoading)
                    Spacer()
                }
            }
        }
    }

    // MARK: Tasks

    private var decompositionPhase: some View {
        let nextNodeID = session.nextRunnableNode()?.id
        return VStack(alignment: .leading, spacing: 14) {
            specificationCard

            if session.nodes.isEmpty {
                card(title: L.t("Task breakdown"), icon: "square.stack.3d.up") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.t("Split the approved specification into tasks that can be checked independently. This step does not write code."))
                            .interfaceFont(size: 12)
                            .foregroundColor(Color.mimo.textSecondary)
                        HStack {
                            Spacer()
                            primaryButton(
                                L.t("Break into tasks"),
                                icon: "square.stack.3d.up",
                                isBusy: session.isLoading
                            ) {
                                Task { await session.generateDecomposition() }
                            }
                            .disabled(session.isLoading)
                        }
                    }
                }
            } else {
                ForEach(session.nodes, id: \.id) { node in
                    decompositionNodeCard(node, isNext: nextNodeID == node.id)
                }

                HStack {
                    Spacer()
                    primaryButton(L.t("Finish and open chat"), icon: "checkmark.circle") {
                        if session.finishWizard(forced: false) {
                            appState.finishSpecWizard(for: session.projectPath)
                        }
                    }
                }
            }
        }
    }

    private func decompositionNodeCard(_ node: ProjectSpecNode, isNext: Bool) -> some View {
        let dependencies = session.dependencies(of: node)
        let acceptance = decodeAcceptance(node.acceptanceCriteriaJSON)
        let hasCodingChat = !session.nodeSessions(for: node.id).isEmpty
        return card(title: "\(node.externalKey) · \(node.title)", icon: "circle.hexagongrid") {
            VStack(alignment: .leading, spacing: 10) {
                nodeStatusBadge(node.status)

                Text(node.description)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !acceptance.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.t("Completion criteria"))
                            .interfaceFont(size: 10, weight: .semibold)
                            .foregroundColor(Color.mimo.textMuted)
                        ForEach(acceptance, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                Text(item)
                            }
                            .interfaceFont(size: 11)
                            .foregroundColor(Color.mimo.textPrimary)
                        }
                    }
                }

                if !dependencies.isEmpty {
                    Text("\(L.t("Depends on")): \(dependencies.map(\.externalKey).joined(separator: ", "))")
                        .interfaceFont(size: 10, design: .monospaced)
                        .foregroundColor(Color.mimo.textMuted)
                }

                nodeActions(node, isNext: isNext, hasCodingChat: hasCodingChat)
            }
        }
    }

    @ViewBuilder
    private func nodeActions(_ node: ProjectSpecNode,
                             isNext: Bool,
                             hasCodingChat: Bool) -> some View {
        HStack(spacing: 8) {
            switch node.status {
            case "pending":
                if isNext {
                    primaryButton(L.t("Start coding"), icon: "play.fill") {
                        appState.startSpecNodeCoding(wizard: session, node: node)
                    }
                } else {
                    Text(L.t("Waiting for dependencies"))
                        .interfaceFont(size: 10)
                        .foregroundColor(Color.mimo.textMuted)
                }
            case "running":
                if hasCodingChat {
                    secondaryButton(L.t("Open coding chat"), icon: "bubble.left") {
                        appState.openSpecNodeChat(wizard: session, nodeID: node.id)
                    }
                }
                secondaryButton(L.t("Mark done"), icon: "checkmark.circle") {
                    session.finishNode(nodeID: node.id, status: "done")
                }
                secondaryButton(L.t("Mark failed"), icon: "xmark.circle") {
                    session.finishNode(nodeID: node.id, status: "failed")
                }
            case "failed", "blocked":
                secondaryButton(L.t("Retry"), icon: "arrow.clockwise") {
                    session.retryNode(nodeID: node.id)
                }
                if hasCodingChat {
                    secondaryButton(L.t("Open coding chat"), icon: "bubble.left") {
                        appState.openSpecNodeChat(wizard: session, nodeID: node.id)
                    }
                }
            case "done", "skipped":
                if hasCodingChat {
                    secondaryButton(L.t("Open coding chat"), icon: "bubble.left") {
                        appState.openSpecNodeChat(wizard: session, nodeID: node.id)
                    }
                }
            default:
                EmptyView()
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private func nodeStatusBadge(_ status: String) -> some View {
        let color = nodeStatusColor(status)
        return Text(nodeStatusLabel(status))
            .interfaceFont(size: 9, weight: .semibold)
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func nodeStatusLabel(_ status: String) -> String {
        switch status {
        case "running": return L.t("Running")
        case "done": return L.t("Done")
        case "failed": return L.t("Failed")
        case "blocked": return L.t("Blocked")
        case "skipped": return L.t("Skipped")
        default: return L.t("Pending")
        }
    }

    private func nodeStatusColor(_ status: String) -> Color {
        switch status {
        case "running": return Color.mimo.cyan
        case "done": return Color.mimo.success
        case "failed": return Color.mimo.error
        case "blocked": return Color.mimo.warning
        default: return Color.mimo.textMuted
        }
    }

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .interfaceFont(size: 10, weight: .semibold)
                Text(title)
                    .interfaceFont(size: 11, weight: .medium)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.mimo.controlBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.mimo.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(HandCursorButtonStyle())
        .foregroundColor(Color.mimo.textPrimary)
    }

    private func decodeAcceptance(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }

    // MARK: Ready

    private var readyPhase: some View {
        card(title: L.t("Plan ready"), icon: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(draft.decompositionNodeCount) \(L.t("tasks")) · v\(draft.specVersion)")
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textSecondary)
                Text(L.t("Chat opens when setup is finished. The specification and all its versions stay in this project."))
                    .interfaceFont(size: 11)
                    .foregroundColor(Color.mimo.textMuted)
                HStack {
                    Spacer()
                    primaryButton(L.t("Finish and open chat"), icon: "checkmark.circle") {
                        if session.finishWizard(forced: false) {
                            appState.finishSpecWizard(for: session.projectPath)
                        }
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            saveStatus
            Spacer()
            Button {
                saveNow()
            } label: {
                Text(L.t("Save draft"))
                    .interfaceFont(size: 12, weight: .medium)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.mimo.controlBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.mimo.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(HandCursorButtonStyle())
            .foregroundColor(Color.mimo.textPrimary)

            Button {
                showFinishConfirmation = true
            } label: {
                Text(L.t("Finish setup"))
                    .interfaceFont(size: 12, weight: .semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.mimo.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(HandCursorButtonStyle())
            .foregroundColor(.white)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch saveState {
        case .idle:
            EmptyView()
        case .saving:
            Text(L.t("Saving…")).interfaceFont(size: 11).foregroundColor(Color.mimo.textMuted)
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").interfaceFont(size: 10)
                Text(L.t("Saved")).interfaceFont(size: 11)
            }
            .foregroundColor(Color.mimo.success)
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").interfaceFont(size: 10)
                Text(L.t("Could not save the draft. Check the project database.")).interfaceFont(size: 11)
            }
            .foregroundColor(Color.mimo.error)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.error)
            Text(message)
                .interfaceFont(size: 11)
                .foregroundColor(Color.mimo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                session.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .interfaceFont(size: 9)
            }
            .buttonStyle(HandCursorButtonStyle())
            .foregroundColor(Color.mimo.textMuted)
        }
        .padding(10)
        .background(Color.mimo.error.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mimo.error.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Checklist

    private var checklistPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t("Setup progress"))
                .interfaceFont(size: 11, weight: .bold, design: .monospaced)
                .tracking(0.8)
                .foregroundColor(Color.mimo.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.mimo.controlBackground)
                        Capsule()
                            .fill(Color.mimo.cyan)
                            .frame(width: geometry.size.width * SpecWizardChecklistLogic.progress(for: draft))
                    }
                }
                .frame(height: 5)
                Text("\(Int((SpecWizardChecklistLogic.progress(for: draft) * 100).rounded()))%")
                    .interfaceFont(size: 10, design: .monospaced)
                    .foregroundColor(Color.mimo.textMuted)
            }

            VStack(alignment: .leading, spacing: 10) {
                checklistRow(id: .models)
                checklistRow(id: .brief)
                checklistRow(id: .interview)
                checklistRow(id: .specification)
                checklistRow(id: .decomposition)
            }

            Spacer()

            if draft.specVersion > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("Specification version"))
                        .interfaceFont(size: 10, weight: .semibold)
                        .foregroundColor(Color.mimo.textMuted)
                    Text("v\(draft.specVersion)")
                        .interfaceFont(size: 12, design: .monospaced)
                        .foregroundColor(Color.mimo.textPrimary)
                }
            }

            Text(L.t("Chat opens after you finish setup for this project."))
                .interfaceFont(size: 10)
                .foregroundColor(Color.mimo.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color.mimo.backgroundAlt)
    }

    /// Every checklist row is also navigation: clicking it reopens that step,
    /// so a restart on a late step can never trap the user there.
    private func checklistRow(id: SpecWizardChecklistLogic.ItemID) -> some View {
        let state = checklist.first(where: { $0.id == id })?.state ?? .pending
        let target = SpecWizardChecklistLogic.step(for: id)
        let isCurrent = visibleStep == target
        let isNavigable = SpecWizardChecklistLogic.isNavigable(id, in: draft)
        return Button {
            session.go(to: target)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon(for: state))
                    .interfaceFont(size: 12)
                    .foregroundColor(color(for: state))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: id))
                        .interfaceFont(size: 12, weight: state == .done ? .semibold : .regular)
                        .foregroundColor(state == .upcoming ? Color.mimo.textMuted : Color.mimo.textPrimary)
                    if let detail = detail(for: id, state: state) {
                        Text(detail)
                            .interfaceFont(size: 10)
                            .foregroundColor(Color.mimo.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isCurrent ? Color.mimo.cyan.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(HandCursorButtonStyle())
        .disabled(!isNavigable || session.isLoading)
        .help(isNavigable ? L.t("Open this step") : L.t("Next setup step"))
    }

    private func title(for id: SpecWizardChecklistLogic.ItemID) -> String {
        switch id {
        case .models: return L.t("Planning and coding models")
        case .brief: return L.t("Project description")
        case .interview: return L.t("Project questions")
        case .specification: return L.t("Specification")
        case .decomposition: return L.t("Task breakdown")
        }
    }

    private func detail(for id: SpecWizardChecklistLogic.ItemID, state: SpecWizardChecklistLogic.ItemState) -> String? {
        switch (id, state) {
        case (.interview, .upcoming), (.decomposition, .upcoming):
            return L.t("Next setup step")
        case (.models, .pending):
            return L.t("Choose both models")
        case (.brief, .pending):
            return L.t("Goal and technologies are required")
        case (.interview, .pending):
            return L.t("Answer the project questions")
        case (.specification, .pending):
            return L.t("Create the specification from your answers")
        case (.decomposition, .pending):
            return L.t("Break the specification into tasks")
        default:
            return nil
        }
    }

    private func icon(for state: SpecWizardChecklistLogic.ItemState) -> String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .pending: return "circle"
        case .upcoming: return "lock.circle"
        }
    }

    private func color(for state: SpecWizardChecklistLogic.ItemState) -> Color {
        switch state {
        case .done: return Color.mimo.success
        case .pending: return Color.mimo.textMuted
        case .upcoming: return Color.mimo.textMuted.opacity(0.7)
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textSecondary)
                Text(title)
                    .interfaceFont(size: 13, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mimo.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.mimo.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func primaryButton(_ title: String, icon: String, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                        .interfaceFont(size: 10, weight: .semibold)
                }
                Text(isBusy ? L.t("Working…") : title)
                    .interfaceFont(size: 12, weight: .semibold)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Color.mimo.brand)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(HandCursorButtonStyle())
        .foregroundColor(.white)
        .opacity(session.isLoading ? 0.55 : 1)
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveState = .saving
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            saveState = session.saveDraft() ? .saved : .failed
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveState = session.saveDraft() ? .saved : .failed
    }

    private func forceFinish() {
        guard session.finishWizard(forced: true) else { return }
        appState.finishSpecWizard(for: session.projectPath)
    }
}
