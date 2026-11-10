import SwiftUI

extension SpecWizardContent {
    // MARK: Phases

    @ViewBuilder
    var phaseContent: some View {
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

    var setupPhase: some View {
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

    var modelsCard: some View {
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

    func openModelSettings() {
        appState.showSettings = true
        appState.settingsTab = .providers
    }

    var briefCard: some View {
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

    func briefField(title: String, placeholder: String, text: Binding<String>, height: CGFloat) -> some View {
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
}
