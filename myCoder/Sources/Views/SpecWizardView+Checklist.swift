import SwiftUI

extension SpecWizardContent {
    // MARK: Checklist

    var checklistPane: some View {
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
    func checklistRow(id: SpecWizardChecklistLogic.ItemID) -> some View {
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

    func title(for id: SpecWizardChecklistLogic.ItemID) -> String {
        switch id {
        case .models: return L.t("Planning and coding models")
        case .brief: return L.t("Project description")
        case .interview: return L.t("Project questions")
        case .specification: return L.t("Specification")
        case .decomposition: return L.t("Task breakdown")
        }
    }

    func detail(for id: SpecWizardChecklistLogic.ItemID, state: SpecWizardChecklistLogic.ItemState) -> String? {
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

    func icon(for state: SpecWizardChecklistLogic.ItemState) -> String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .pending: return "circle"
        case .upcoming: return "lock.circle"
        }
    }

    func color(for state: SpecWizardChecklistLogic.ItemState) -> Color {
        switch state {
        case .done: return Color.mimo.success
        case .pending: return Color.mimo.textMuted
        case .upcoming: return Color.mimo.textMuted.opacity(0.7)
        }
    }
}
