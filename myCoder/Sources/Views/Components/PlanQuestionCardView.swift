import SwiftUI

struct PlanQuestionCardView: View {
    let questions: [PlanQuestion]
    let onSubmit: ([[String]]) -> Void

    @State private var currentStep = 0
    @State private var selections: [String: Set<String>] = [:]
    @State private var otherTexts: [String: String] = [:]

    private var theme: PlanQuestionWizardTheme { .current }

    var body: some View {
        SciFiWizardPanel(theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
                wizardHeader

                if let question = currentQuestion {
                    questionStep(question)
                        .id(question.id)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                wizardFooter
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentStep)
    }

    private var currentQuestion: PlanQuestion? {
        guard questions.indices.contains(currentStep) else { return nil }
        return questions[currentStep]
    }

    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(theme.accent)
                Text(theme.headerTitle)
                    .interfaceFont(size: 11, weight: .bold, design: .monospaced)
                    .tracking(1.1)
                    .foregroundColor(theme.accent)
                Spacer(minLength: 0)
                if questions.count > 1 {
                    Text(PlanQuestionWizardLogic.progressLabel(step: currentStep, total: questions.count))
                        .interfaceFont(size: 10, weight: .bold, design: .monospaced)
                        .foregroundColor(theme.accentSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.secondaryButtonFill)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(theme.optionBorder, lineWidth: 1)
                        )
                }
            }

            if questions.count > 1 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.progressTrack)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [theme.accent, theme.accentSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * PlanQuestionWizardLogic.progressFraction(
                                step: currentStep,
                                total: questions.count
                            ))
                            .shadow(color: theme.glowColor, radius: 4)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    @ViewBuilder
    private func questionStep(_ question: PlanQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question.header.uppercased())
                .interfaceFont(size: 10, weight: .bold, design: .monospaced)
                .tracking(0.8)
                .foregroundColor(Color.mimo.textMuted)
            Text(question.prompt)
                .interfaceFont(size: 14, weight: .semibold)
                .foregroundColor(Color.mimo.textPrimary)

            ForEach(question.options) { option in
                optionCard(option, for: question)
            }

            TextField(L.t(AppLocalizationKey.locOtherAnswer), text: binding(for: question.id))
                .textFieldStyle(.plain)
                .interfaceFont(size: 12, design: .monospaced)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(theme.optionFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.optionBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func optionCard(_ option: PlanQuestionOption, for question: PlanQuestion) -> some View {
        let selected = isSelected(option.id, question: question)

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: option.id, question: question))
                .interfaceFont(size: 12)
                .foregroundColor(selected ? theme.accent : Color.mimo.textMuted)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .interfaceFont(size: 12, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                if !option.description.isEmpty {
                    Text(option.description)
                        .interfaceFont(size: 11)
                        .foregroundColor(Color.mimo.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? theme.optionSelectedFill : theme.optionFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? theme.optionSelectedBorder : theme.optionBorder, lineWidth: selected ? 1.2 : 1)
        )
        .shadow(color: selected ? theme.glowColor : .clear, radius: 6)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            toggle(option.id, for: question)
        }
    }

    private var wizardFooter: some View {
        HStack(spacing: 8) {
            if questions.count > 1, PlanQuestionWizardLogic.previousStep(from: currentStep) != nil {
                Button(action: goBack) {
                    Text(L.t(AppLocalizationKey.locBack))
                        .interfaceFont(size: 11, weight: .semibold, design: .monospaced)
                        .foregroundColor(Color.mimo.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(theme.secondaryButtonFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.optionBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(HandCursorButtonStyle())
            }

            if PlanQuestionWizardLogic.isLastStep(step: currentStep, total: questions.count) {
                SciFiPrimaryButton(title: L.t(AppLocalizationKey.locTransmit), enabled: canSubmit, theme: theme, action: submit)
            } else {
                SciFiPrimaryButton(title: L.t(AppLocalizationKey.locNext), enabled: canAdvance, theme: theme, action: goNext)
            }
        }
    }

    private var canAdvance: Bool {
        PlanQuestionWizardLogic.canAdvance(
            step: currentStep,
            questions: questions,
            selections: selections,
            otherTexts: otherTexts
        )
    }

    private var canSubmit: Bool {
        PlanQuestionWizardLogic.allAnswered(
            questions: questions,
            selections: selections,
            otherTexts: otherTexts
        )
    }

    private func goBack() {
        guard let previous = PlanQuestionWizardLogic.previousStep(from: currentStep) else { return }
        currentStep = previous
    }

    private func goNext() {
        guard canAdvance,
              let next = PlanQuestionWizardLogic.nextStep(from: currentStep, total: questions.count) else { return }
        currentStep = next
    }

    private func submit() {
        let answers = PlanQuestionLogic.buildReplyAnswers(
            questions: questions,
            selections: selections,
            otherTexts: otherTexts
        )
        onSubmit(answers)
    }

    private func toggle(_ optionID: String, for question: PlanQuestion) {
        var selected = selections[question.id] ?? []
        if question.allowsMultiple {
            if selected.contains(optionID) {
                selected.remove(optionID)
            } else {
                selected.insert(optionID)
            }
        } else {
            selected = [optionID]
        }
        selections[question.id] = selected
    }

    private func isSelected(_ optionID: String, question: PlanQuestion) -> Bool {
        selections[question.id]?.contains(optionID) == true
    }

    private func iconName(for optionID: String, question: PlanQuestion) -> String {
        isSelected(optionID, question: question)
            ? (question.allowsMultiple ? "checkmark.square.fill" : "largecircle.fill.circle")
            : (question.allowsMultiple ? "square" : "circle")
    }

    private func binding(for questionID: String) -> Binding<String> {
        Binding(
            get: { otherTexts[questionID] ?? "" },
            set: { otherTexts[questionID] = $0 }
        )
    }
}

extension Notification.Name {
    static let submitPlanQuestionAnswers = Notification.Name("MiMoSubmitPlanQuestionAnswers")
}
