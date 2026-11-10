import SwiftUI

extension SpecWizardContent {
    // MARK: Questions

    /// One visible progress line for every long step (interview, summary,
    /// specification, decomposition), so the wizard never looks frozen.
    var busyBanner: some View {
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

    var interviewPhase: some View {
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
    var feedCard: some View {
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
    var feedTurns: [SpecPlannerTurn] {
        let history = SpecWizardInterviewLayoutLogic.history(
            session.turns,
            excludingLiveQuestion: session.isQuestionCardVisible && session.currentQuestion != nil
        )
        return SpecWizardInterviewLayoutLogic.newestFirst(history)
    }

    /// What the planner understood, with a way to correct it before the
    /// specification is written.
    func completionCard(_ summary: String) -> some View {
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

    func interviewTurn(_ turn: SpecPlannerTurn) -> some View {
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

    func plannerDisplayText(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let question = try? JSONDecoder().decode(SpecInterviewQuestion.self, from: data) else {
            return raw
        }
        if question.done {
            return question.summary ?? L.t("Questions complete")
        }
        return question.question
    }

    func questionCard(_ question: SpecInterviewQuestion) -> some View {
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

    func submit(_ answer: String) {
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
    func submitClarification() {
        let clean = clarifyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        clarifyText = ""
        Task {
            let ok = await session.clarify(clean)
            if !ok, session.errorMessage != nil, clarifyText.isEmpty { clarifyText = clean }
        }
    }
}
