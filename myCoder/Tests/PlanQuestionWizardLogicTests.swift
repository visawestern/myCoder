import Testing
@testable import myCoder

@Suite("Plan question wizard")
struct PlanQuestionWizardLogicTests {

    private let question = PlanQuestion(
        id: "q-0",
        header: "Scope",
        prompt: "What next?",
        options: [
            PlanQuestionOption(id: "opt-0", label: "UI", description: ""),
            PlanQuestionOption(id: "opt-1", label: "Logic", description: "")
        ],
        allowsMultiple: false
    )

    @Test("Detects answered question from selection or other text")
    func detectsAnsweredQuestion() {
        #expect(
            PlanQuestionWizardLogic.isQuestionAnswered(
                question,
                selections: ["q-0": ["opt-0"]],
                otherTexts: [:]
            )
        )
        #expect(
            PlanQuestionWizardLogic.isQuestionAnswered(
                question,
                selections: [:],
                otherTexts: ["q-0": "Custom"]
            )
        )
        #expect(
            PlanQuestionWizardLogic.isQuestionAnswered(
                question,
                selections: [:],
                otherTexts: ["q-0": "   "]
            ) == false
        )
    }

    @Test("Advances only when current step is answered")
    func advanceRequiresAnswer() {
        let questions = [question, PlanQuestion(
            id: "q-1",
            header: "Next",
            prompt: "Pick",
            options: [PlanQuestionOption(id: "opt-0", label: "A", description: "")],
            allowsMultiple: false
        )]

        #expect(
            PlanQuestionWizardLogic.canAdvance(
                step: 0,
                questions: questions,
                selections: [:],
                otherTexts: [:]
            ) == false
        )
        #expect(
            PlanQuestionWizardLogic.canAdvance(
                step: 0,
                questions: questions,
                selections: ["q-0": ["opt-1"]],
                otherTexts: [:]
            )
        )
    }

    @Test("Tracks last step and progress label")
    func lastStepAndProgress() {
        #expect(PlanQuestionWizardLogic.isLastStep(step: 0, total: 1))
        #expect(PlanQuestionWizardLogic.isLastStep(step: 0, total: 3) == false)
        #expect(PlanQuestionWizardLogic.isLastStep(step: 2, total: 3))
        #expect(PlanQuestionWizardLogic.progressLabel(step: 1, total: 4) == "2 / 4")
    }

    @Test("Clamps step navigation")
    func stepNavigation() {
        #expect(PlanQuestionWizardLogic.previousStep(from: 0) == nil)
        #expect(PlanQuestionWizardLogic.previousStep(from: 2) == 1)
        #expect(PlanQuestionWizardLogic.nextStep(from: 0, total: 3) == 1)
        #expect(PlanQuestionWizardLogic.nextStep(from: 2, total: 3) == nil)
    }
}
