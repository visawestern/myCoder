import Testing
import Foundation
@testable import myCoder

@Suite("SmartElementFinder Tests")
struct SmartElementFinderTests {

    // MARK: - ElementType Tests

    @Test("ElementType has correct class keywords")
    func testElementTypeKeywords() {
        #expect(ElementType.sendButton.classKeywords.contains("send"))
        #expect(ElementType.sendButton.classKeywords.contains("submit"))
        #expect(ElementType.input.classKeywords.contains("input"))
        #expect(ElementType.input.classKeywords.contains("editor"))
        #expect(ElementType.modelDropdown.classKeywords.contains("model"))
        #expect(ElementType.modelDropdown.classKeywords.contains("dropdown"))
        #expect(ElementType.newChat.classKeywords.contains("new-chat"))
        #expect(ElementType.effortToggle.classKeywords.contains("effort"))
        #expect(ElementType.stopButton.classKeywords.contains("stop"))
    }

    @Test("ElementType has correct aria keywords")
    func testElementTypeAriaKeywords() {
        #expect(ElementType.sendButton.ariaKeywords.contains("send"))
        #expect(ElementType.sendButton.ariaKeywords.contains("отправить"))
        #expect(ElementType.input.ariaKeywords.contains("message"))
        #expect(ElementType.modelDropdown.ariaKeywords.contains("model"))
        #expect(ElementType.newChat.ariaKeywords.contains("new chat"))
    }

    @Test("ElementType has correct SVG icon names")
    func testElementTypeSVGNames() {
        #expect(ElementType.sendButton.svgIconNames.contains("Send"))
        #expect(ElementType.sendButton.svgIconNames.contains("PaperPlane"))
        #expect(ElementType.newChat.svgIconNames.contains("Plus"))
        #expect(ElementType.newChat.svgIconNames.contains("Add"))
        #expect(ElementType.stopButton.svgIconNames.contains("Stop"))
    }

    @Test("ElementType description is human-readable")
    func testElementTypeDescription() {
        #expect(!ElementType.sendButton.description.isEmpty)
        #expect(!ElementType.input.description.isEmpty)
        #expect(!ElementType.modelDropdown.description.isEmpty)
        #expect(!ElementType.newChat.description.isEmpty)
        #expect(!ElementType.unknown.description.isEmpty)
    }

    // MARK: - Classification Tests

    @Test("Classify send button by CSS class")
    func testClassifySendButtonByClass() {
        let result = SmartElementFinder.classifyElement(
            tagName: "button",
            classes: ["send-btn", "primary"],
            ariaLabel: "",
            text: "",
            role: "",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .sendButton)
    }

    @Test("Classify send button by aria-label")
    func testClassifySendButtonByAria() {
        let result = SmartElementFinder.classifyElement(
            tagName: "div",
            classes: [],
            ariaLabel: "Send message",
            text: "",
            role: "button",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .sendButton)
    }

    @Test("Classify send button by SVG icon")
    func testClassifySendButtonBySVG() {
        let result = SmartElementFinder.classifyElement(
            tagName: "button",
            classes: [],
            ariaLabel: "",
            text: "",
            role: "",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "PaperPlane",
            dataTestId: "",
            position: nil
        )
        #expect(result == .sendButton)
    }

    @Test("Classify input by contenteditable")
    func testClassifyInputByContentEditable() {
        let result = SmartElementFinder.classifyElement(
            tagName: "div",
            classes: ["editor"],
            ariaLabel: "",
            text: "",
            role: "textbox",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "Type a message...",
            contentEditable: "true",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .input)
    }

    @Test("Classify input by textarea tag")
    func testClassifyInputByTag() {
        let result = SmartElementFinder.classifyElement(
            tagName: "textarea",
            classes: [],
            ariaLabel: "",
            text: "",
            role: "",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "Ask anything",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .input)
    }

    @Test("Classify model dropdown by aria-haspopup")
    func testClassifyModelDropdownByAria() {
        let result = SmartElementFinder.classifyElement(
            tagName: "button",
            classes: [],
            ariaLabel: "",
            text: "GPT-4",
            role: "",
            ariaHasPopup: "listbox",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .modelDropdown)
    }

    @Test("Classify model dropdown by CSS class")
    func testClassifyModelDropdownByClass() {
        let result = SmartElementFinder.classifyElement(
            tagName: "div",
            classes: ["model-selector", "dropdown"],
            ariaLabel: "",
            text: "",
            role: "combobox",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .modelDropdown)
    }

    @Test("Classify new chat by CSS class")
    func testClassifyNewChatByClass() {
        let result = SmartElementFinder.classifyElement(
            tagName: "button",
            classes: ["new-chat-btn"],
            ariaLabel: "",
            text: "",
            role: "",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .newChat)
    }

    @Test("Classify new chat by SVG icon")
    func testClassifyNewChatBySVG() {
        let result = SmartElementFinder.classifyElement(
            tagName: "div",
            classes: [],
            ariaLabel: "",
            text: "",
            role: "button",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "Plus",
            dataTestId: "",
            position: nil
        )
        #expect(result == .newChat)
    }

    @Test("Classify effort toggle by CSS class")
    func testClassifyEffortByClass() {
        let result = SmartElementFinder.classifyElement(
            tagName: "div",
            classes: ["effort-selector"],
            ariaLabel: "",
            text: "",
            role: "",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .effortToggle)
    }

    @Test("Classify stop button by SVG icon")
    func testClassifyStopBySVG() {
        let result = SmartElementFinder.classifyElement(
            tagName: "button",
            classes: [],
            ariaLabel: "",
            text: "",
            role: "",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "Stop",
            dataTestId: "",
            position: nil
        )
        #expect(result == .stopButton)
    }

    @Test("Classify unknown element")
    func testClassifyUnknown() {
        let result = SmartElementFinder.classifyElement(
            tagName: "span",
            classes: ["random-class"],
            ariaLabel: "",
            text: "Hello",
            role: "",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .unknown)
    }

    // MARK: - SmartElementResult Tests

    @Test("SmartElementResult encodes and decodes correctly")
    func testSmartElementResultCodable() throws {
        let result = SmartElementResult(
            selector: ".send-btn",
            confidence: 0.85,
            method: "smart-classify",
            elementType: .sendButton,
            text: "Send",
            ariaLabel: "Send message",
            classes: ["send-btn", "primary"],
            tagName: "button",
            isVisible: true,
            isEnabled: true,
            position: ElementPosition(x: 100, y: 200, width: 40, height: 40)
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SmartElementResult.self, from: data)

        #expect(decoded.selector == ".send-btn")
        #expect(decoded.confidence == 0.85)
        #expect(decoded.method == "smart-classify")
        #expect(decoded.elementType == .sendButton)
        #expect(decoded.text == "Send")
        #expect(decoded.ariaLabel == "Send message")
        #expect(decoded.classes == ["send-btn", "primary"])
        #expect(decoded.tagName == "button")
        #expect(decoded.isVisible == true)
        #expect(decoded.isEnabled == true)
        #expect(decoded.position?.x == 100)
        #expect(decoded.position?.y == 200)
    }

    @Test("DOMAnalysis encodes and decodes correctly")
    func testDOMAnalysisCodable() throws {
        let element = ElementInfo(
            selector: "#send-btn",
            tagName: "button",
            text: "Send",
            ariaLabel: "Send",
            classes: ["send"],
            isVisible: true,
            isEnabled: true,
            position: nil,
            elementType: .sendButton,
            confidence: 0.9
        )

        let analysis = DOMAnalysis(
            buttons: [element],
            inputs: [],
            dropdowns: [],
            links: [],
            allInteractive: [element]
        )

        let data = try JSONEncoder().encode(analysis)
        let decoded = try JSONDecoder().decode(DOMAnalysis.self, from: data)

        #expect(decoded.buttons.count == 1)
        #expect(decoded.buttons[0].selector == "#send-btn")
        #expect(decoded.inputs.isEmpty)
        #expect(decoded.allInteractive.count == 1)
    }

    // MARK: - Edge Cases

    @Test("Classification handles empty classes")
    func testClassificationEmptyClasses() {
        let result = SmartElementFinder.classifyElement(
            tagName: "button",
            classes: [],
            ariaLabel: "Send",
            text: "",
            role: "",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: nil
        )
        #expect(result == .sendButton)
    }

    @Test("Classification handles multiple matching keywords")
    func testClassificationMultipleKeywords() {
        let result = SmartElementFinder.classifyElement(
            tagName: "button",
            classes: ["send-btn", "submit-btn"],
            ariaLabel: "Send message",
            text: "Send",
            role: "",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "Send",
            dataTestId: "send-button",
            position: nil
        )
        #expect(result == .sendButton)
    }

    @Test("Position-based heuristics work for send button")
    func testPositionHeuristics() {
        let result = SmartElementFinder.classifyElement(
            tagName: "div",
            classes: [],
            ariaLabel: "",
            text: "",
            role: "button",
            ariaHasPopup: "",
            inputType: "",
            placeholder: "",
            contentEditable: "",
            svgName: "",
            dataTestId: "",
            position: ElementPosition(x: 350, y: 500, width: 40, height: 40)
        )
        // Position should boost send button confidence
        #expect(result == .sendButton)
    }
}
