import Testing
@testable import myCoder

@Suite("Message response merge")
struct MessageResponseMergeLogicTests {

    @Test("Server response replaces streamed parts instead of duplicating text")
    func replacesDuplicateTextParts() {
        let existing = Message(
            role: .assistant,
            content: "Answer",
            parts: [.text("Answer")],
            reasoning: "thinking"
        )

        let merged = MessageResponseMergeLogic.mergedAssistantMessage(
            existing: existing,
            serverParts: [.text("Answer"), .reasoning("thinking")],
            serverText: "Answer",
            streamingText: "Answer"
        )

        #expect(merged.content == "Answer")
        #expect(merged.parts.filter {
            if case .text = $0 { return true }
            return false
        }.count == 1)
    }

    @Test("Reasoning hidden when it duplicates visible answer")
    func hidesDuplicateReasoning() {
        let message = Message(
            role: .assistant,
            content: "Same text",
            parts: [.reasoning("Same text"), .text("Same text")]
        )
        #expect(MessageResponseMergeLogic.reasoningForDisplay(message).isEmpty)
    }
}

@Suite("Plan question parsing")
struct PlanQuestionLogicTests {

    @Test("Detects AskUserQuestion tool names")
    func detectsQuestionTool() {
        #expect(PlanQuestionLogic.isQuestionTool("AskUserQuestion"))
        #expect(PlanQuestionLogic.isQuestionTool("mcp__user__ask_user"))
        #expect(PlanQuestionLogic.isQuestionTool("question"))
    }

    @Test("Parses OpenCode question.asked event properties")
    func parsesQuestionAskedEvent() {
        let props: [String: Any] = [
            "requestID": "req_abc",
            "sessionID": "ses_123",
            "questions": [
                [
                    "header": "Project type",
                    "question": "Choose project type",
                    "multiple": false,
                    "options": [
                        ["label": "NSFC", "description": "Grant proposal"]
                    ]
                ]
            ]
        ]

        let parsed = PlanQuestionLogic.parseQuestionAskedEvent(properties: props)
        #expect(parsed?.requestID == "req_abc")
        #expect(parsed?.sessionID == "ses_123")
        #expect(parsed?.questions.count == 1)
        #expect(parsed?.questions[0].options.first?.label == "NSFC")
        #expect(parsed?.questions[0].allowsMultiple == false)
    }

    @Test("Parses OpenCode tool part with nested state input")
    func parsesOpenCodeToolPart() {
        let part: [String: Any] = [
            "type": "tool",
            "tool": "question",
            "callID": "call_1",
            "state": [
                "status": "running",
                "input": [
                    "questions": [
                        [
                            "header": "Scope",
                            "question": "What next?",
                            "options": [
                                ["label": "UI", "description": ""]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let parsed = PlanQuestionLogic.parseOpenCodeToolPart(part)
        #expect(parsed?.toolName == "question")
        #expect(parsed?.isPending == true)
        #expect(parsed?.questions.count == 1)
        #expect(parsed?.questions[0].prompt == "What next?")
    }

    @Test("Builds reply answers payload for question API")
    func buildsReplyAnswers() {
        let questions = [
            PlanQuestion(
                id: "q-0",
                header: "Scope",
                prompt: "What next?",
                options: [
                    PlanQuestionOption(id: "opt-0", label: "UI", description: ""),
                    PlanQuestionOption(id: "opt-1", label: "Logic", description: "")
                ],
                allowsMultiple: false
            )
        ]
        let answers = PlanQuestionLogic.buildReplyAnswers(
            questions: questions,
            selections: ["q-0": ["opt-0"]],
            otherTexts: [:]
        )
        #expect(answers == [["UI"]])
    }

    @Test("Detects pending question tool parts")
    func detectsPendingQuestionParts() {
        let args = """
        {"questions":[{"question":"Pick one","options":[{"label":"A","description":""}]}]}
        """
        let parts: [MessagePartContent] = [
            .toolCall(name: "question", args: args, result: nil, callID: "call-1")
        ]
        #expect(PlanQuestionLogic.hasPendingQuestions(in: parts))
    }

    @Test("Parses interactive plan questions from tool args")
    func parsesQuestions() throws {
        let json = """
        {
          "questions": [
            {
              "header": "Scope",
              "question": "What should we improve first?",
              "options": [
                {"label": "UI", "description": "Visual polish"},
                {"label": "Logic", "description": "Behavior fixes"}
              ]
            }
          ]
        }
        """
        let questions = PlanQuestionLogic.parseQuestions(from: json)
        #expect(questions.count == 1)
        #expect(questions[0].options.count == 2)
    }
}
