import SwiftUI

extension SpecWizardContent {
    // MARK: Specification

    @ViewBuilder
    var specificationPhase: some View {
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

    var specificationCard: some View {
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
}
