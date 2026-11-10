import SwiftUI

extension SpecWizardContent {
    // MARK: Header

    var visibleStep: SpecWizardStep {
        let furthest = draft.furthestStep
        guard let active = draft.activeStep, active.rank <= furthest.rank else { return furthest }
        guard draft.status != .draft else { return active }
        // A finished project opens on its task board, but an explicit return
        // to an earlier phase is still honored.
        if active.rank < SpecWizardStep.ready.rank { return active }
        return session.nodes.isEmpty ? .ready : .decomposition
    }

    var stepNumber: Int {
        switch visibleStep {
        case .setup: return 1
        case .interview: return 2
        case .specification: return 3
        case .decomposition: return 4
        case .ready: return 4
        }
    }

    var header: some View {
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

    var phaseTitle: String {
        switch visibleStep {
        case .setup: return "Setup"
        case .interview: return "Questions"
        case .specification: return "Specification"
        case .decomposition: return "Tasks"
        case .ready: return "Ready"
        }
    }

    var phaseSubtitle: String {
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
}
