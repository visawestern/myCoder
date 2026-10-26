import Testing
import Foundation
@testable import myCoder

@Suite("Spec planner logic")
struct SpecPlannerLogicTests {

    @Test("Interview JSON inside a markdown fence is decoded")
    func interviewFencedJSON() throws {
        let raw = """
        Sure — next question:
        ```json
        {"id":"scope","question":"Which platforms?","suggested_answers":["macOS","iOS","both"],"done":false}
        ```
        """
        let question = try SpecInterviewLogic.decode(raw)
        #expect(question.id == "scope")
        #expect(question.question == "Which platforms?")
        #expect(question.suggestedAnswers == ["macOS", "iOS", "both"])
        #expect(question.done == false)
    }

    @Test("Interview suggestions are trimmed and deduplicated")
    func interviewSuggestionsNormalized() throws {
        let raw = """
        {"id":"stack","question":"Stack?","suggested_answers":[" Swift ","Swift","","UIKit"],"done":false}
        """
        let question = try SpecInterviewLogic.decode(raw)
        #expect(question.suggestedAnswers == ["Swift", "UIKit"])
    }

    @Test("A finished interview may omit the question text")
    func interviewDoneWithoutQuestion() throws {
        let raw = #"{"id":"final","done":true,"summary":"Enough to write the spec"}"#
        let question = try SpecInterviewLogic.decode(raw)
        #expect(question.done)
        #expect(question.summary == "Enough to write the spec")
        #expect(question.suggestedAnswers.isEmpty)
    }

    @Test("Interview without a JSON object is rejected")
    func interviewRejectsPlainText() {
        #expect(throws: SpecPlannerParseError.self) {
            _ = try SpecInterviewLogic.decode("What should we build?")
        }
    }

    @Test("An unfinished interview question must have text and an id")
    func interviewRejectsEmptyQuestion() {
        #expect(throws: SpecPlannerParseError.self) {
            _ = try SpecInterviewLogic.decode(#"{"id":"scope","question":"   ","done":false}"#)
        }
        #expect(throws: SpecPlannerParseError.self) {
            _ = try SpecInterviewLogic.decode(#"{"id":"","question":"Which?","done":false}"#)
        }
    }

    @Test("Decomposition decodes dependencies and orders nodes")
    func decompositionDecodes() throws {
        let raw = """
        ```json
        {"nodes":[
          {"key":"N2","title":"UI","description":"Build the screen","kind":"task","order":2,
           "acceptance_criteria":["Screen renders"],"depends_on":["N1"]},
          {"key":"N1","title":"Store","description":"Persist data","kind":"task","order":1,
           "acceptance_criteria":["Data survives restart"],"depends_on":[]}
        ]}
        ```
        """
        let decomposition = try SpecDecompositionLogic.decode(raw)
        #expect(decomposition.nodes.count == 2)
        #expect(decomposition.nodes[0].key == "N1")
        #expect(decomposition.nodes[1].dependsOn == ["N1"])
        #expect(decomposition.nextNode(completed: [])?.key == "N1")
        #expect(decomposition.nextNode(completed: ["N1"])?.key == "N2")
        #expect(decomposition.nextNode(completed: ["N1", "N2"]) == nil)
    }

    @Test("Decomposition rejects duplicate keys")
    func decompositionRejectsDuplicates() throws {
        let duplicate = """
        {"nodes":[
          {"key":"N1","title":"A","description":"A","kind":"task","acceptance_criteria":["ok"],"depends_on":[]},
          {"key":"N1","title":"B","description":"B","kind":"task","acceptance_criteria":["ok"],"depends_on":[]}
        ]}
        """
        #expect(throws: SpecDecompositionError.self) {
            _ = try SpecDecompositionLogic.decode(duplicate)
        }
    }

    @Test("Decomposition rejects missing dependencies and self cycles")
    func decompositionRejectsBadEdges() throws {
        let missing = """
        {"nodes":[
          {"key":"N1","title":"A","description":"A","kind":"task","acceptance_criteria":["ok"],"depends_on":["N9"]}
        ]}
        """
        #expect(throws: SpecDecompositionError.self) {
            _ = try SpecDecompositionLogic.decode(missing)
        }

        let selfCycle = """
        {"nodes":[
          {"key":"N1","title":"A","description":"A","kind":"task","acceptance_criteria":["ok"],"depends_on":["N1"]}
        ]}
        """
        #expect(throws: SpecDecompositionError.self) {
            _ = try SpecDecompositionLogic.decode(selfCycle)
        }
    }

    @Test("Decomposition rejects cycles between nodes")
    func decompositionRejectsCycle() throws {
        let raw = """
        {"nodes":[
          {"key":"N1","title":"A","description":"A","kind":"task","acceptance_criteria":["ok"],"depends_on":["N2"]},
          {"key":"N2","title":"B","description":"B","kind":"task","acceptance_criteria":["ok"],"depends_on":["N1"]}
        ]}
        """
        #expect(throws: SpecDecompositionError.self) {
            _ = try SpecDecompositionLogic.decode(raw)
        }
    }

    @Test("Decomposition requires acceptance criteria for every node")
    func decompositionRequiresAcceptance() throws {
        let raw = """
        {"nodes":[
          {"key":"N1","title":"A","description":"A","kind":"task","acceptance_criteria":[],"depends_on":[]}
        ]}
        """
        #expect(throws: SpecDecompositionError.self) {
            _ = try SpecDecompositionLogic.decode(raw)
        }
    }

    @Test("Chat is blocked only while the wizard is a draft")
    func gateBlocksDraftOnly() {
        var draft = SpecWizardDraft()
        draft.status = .draft
        #expect(SpecWizardGateLogic.shouldBlockChat(draft))

        draft.status = .forced
        #expect(!SpecWizardGateLogic.shouldBlockChat(draft))

        draft.status = .complete
        #expect(!SpecWizardGateLogic.shouldBlockChat(draft))

        #expect(!SpecWizardGateLogic.shouldBlockChat(nil))
    }

    @Test("Revision numbers are monotonic and start at one")
    func revisionVersions() {
        #expect(SpecRevisionLogic.nextVersion(existing: []) == 1)
        #expect(SpecRevisionLogic.nextVersion(existing: [1, 4, 2]) == 5)
        #expect(SpecRevisionLogic.isValid(content: "  ") == false)
        #expect(SpecRevisionLogic.isValid(content: "# Spec") == true)
    }
}
