import SwiftUI

extension SpecWizardContent {
    // MARK: Ready

    var readyPhase: some View {
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

    var footer: some View {
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
    var saveStatus: some View {
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

    func errorBanner(_ message: String) -> some View {
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
}
