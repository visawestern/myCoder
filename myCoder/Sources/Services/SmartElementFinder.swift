import Foundation

/// Classifies web UI elements by their function (send button, input, dropdown, etc.)
///
/// Used by `SmartElementFinder` to identify elements when catalog selectors fail.
/// Classification is based on CSS classes, aria attributes, DOM position, and element type.
///
/// ## Classification Algorithm
/// 1. Check element tag (button, input, textarea, div)
/// 2. Check CSS classes for keywords (send, submit, model, chat, input)
/// 3. Check aria-label and aria-describedby for semantic meaning
/// 4. Check data-testid, data-test, data-cy attributes
/// 5. Check position in DOM (parent containers)
/// 6. Check element size and visibility
/// 7. Check placeholder text for inputs
/// 8. Check contenteditable attribute
enum ElementType: String, CaseIterable, Codable {
    case sendButton
    case input
    case modelDropdown
    case newChat
    case effortToggle
    case stopButton
    case settingsButton
    case loginButton
    case logoutButton
    case profileButton
    case searchButton
    case menuButton
    case backButton
    case closeButton
    case confirmButton
    case cancelButton
    case uploadButton
    case attachButton
    case voiceButton
    case imageButton
    case codeButton
    case linkButton
    case emojiButton
    case moreButton
    case refreshButton
    case shareButton
    case copyButton
    case deleteButton
    case editButton
    case saveButton
    case submitButton
    case resetButton
    case unknown

    /// Human-readable description of the element type
    var description: String {
        switch self {
        case .sendButton: return "Send message button"
        case .input: return "Text input field"
        case .modelDropdown: return "Model selection dropdown"
        case .newChat: return "New chat button"
        case .effortToggle: return "Effort/thinking level toggle"
        case .stopButton: return "Stop generation button"
        case .settingsButton: return "Settings button"
        case .loginButton: return "Login button"
        case .logoutButton: return "Logout button"
        case .profileButton: return "Profile button"
        case .searchButton: return "Search button"
        case .menuButton: return "Menu button"
        case .backButton: return "Back button"
        case .closeButton: return "Close button"
        case .confirmButton: return "Confirm button"
        case .cancelButton: return "Cancel button"
        case .uploadButton: return "Upload button"
        case .attachButton: return "Attach file button"
        case .voiceButton: return "Voice input button"
        case .imageButton: return "Image button"
        case .codeButton: return "Code button"
        case .linkButton: return "Link button"
        case .emojiButton: return "Emoji button"
        case .moreButton: return "More options button"
        case .refreshButton: return "Refresh button"
        case .shareButton: return "Share button"
        case .copyButton: return "Copy button"
        case .deleteButton: return "Delete button"
        case .editButton: return "Edit button"
        case .saveButton: return "Save button"
        case .submitButton: return "Submit button"
        case .resetButton: return "Reset button"
        case .unknown: return "Unknown element"
        }
    }

    /// CSS class keywords that indicate this element type
    var classKeywords: [String] {
        switch self {
        case .sendButton:
            return ["send", "submit", "send-btn", "send-button", "submit-btn", "submit-button"]
        case .input:
            return ["input", "editor", "composer", "textarea", "message-input", "chat-input"]
        case .modelDropdown:
            return ["model", "dropdown", "select", "switcher", "picker"]
        case .newChat:
            return ["new-chat", "new-chat-btn", "create-chat", "start-chat"]
        case .effortToggle:
            return ["effort", "thinking", "reasoning", "deep-think"]
        case .stopButton:
            return ["stop", "cancel", "abort"]
        case .settingsButton:
            return ["settings", "config", "preferences", "gear"]
        case .loginButton:
            return ["login", "sign-in", "signin"]
        case .logoutButton:
            return ["logout", "sign-out", "signout"]
        case .profileButton:
            return ["profile", "avatar", "user"]
        case .searchButton:
            return ["search", "find", "magnif"]
        case .menuButton:
            return ["menu", "hamburger", "nav"]
        case .backButton:
            return ["back", "prev", "previous"]
        case .closeButton:
            return ["close", "dismiss", "x"]
        case .confirmButton:
            return ["confirm", "ok", "yes", "accept"]
        case .cancelButton:
            return ["cancel", "no", "reject"]
        case .uploadButton:
            return ["upload", "file-upload"]
        case .attachButton:
            return ["attach", "attachment", "paperclip"]
        case .voiceButton:
            return ["voice", "mic", "microphone", "audio"]
        case .imageButton:
            return ["image", "photo", "picture", "img"]
        case .codeButton:
            return ["code", "code-block", "snippet"]
        case .linkButton:
            return ["link", "url", "href"]
        case .emojiButton:
            return ["emoji", "smiley", "emotion"]
        case .moreButton:
            return ["more", "overflow", "dots"]
        case .refreshButton:
            return ["refresh", "reload", "sync"]
        case .shareButton:
            return ["share", "export"]
        case .copyButton:
            return ["copy", "clipboard"]
        case .deleteButton:
            return ["delete", "remove", "trash"]
        case .editButton:
            return ["edit", "pencil", "pen"]
        case .saveButton:
            return ["save", "disk"]
        case .submitButton:
            return ["submit"]
        case .resetButton:
            return ["reset", "clear"]
        case .unknown:
            return []
        }
    }

    /// Aria-label keywords that indicate this element type
    var ariaKeywords: [String] {
        switch self {
        case .sendButton:
            return ["send", "submit", "отправить"]
        case .input:
            return ["message", "chat", "input", "compose"]
        case .modelDropdown:
            return ["model", "select model", "choose model"]
        case .newChat:
            return ["new chat", "create chat", "новый чат"]
        case .effortToggle:
            return ["effort", "thinking", "reasoning"]
        case .stopButton:
            return ["stop", "cancel", "остановить"]
        case .loginButton:
            return ["login", "sign in", "войти"]
        case .logoutButton:
            return ["logout", "sign out", "выйти"]
        case .profileButton:
            return ["profile", "account", "профиль"]
        case .searchButton:
            return ["search", "find", "поиск"]
        default:
            return []
        }
    }

    /// SVG icon names that indicate this element type
    var svgIconNames: [String] {
        switch self {
        case .sendButton:
            return ["Send", "PaperPlane", "ArrowUp", "SendIcon"]
        case .newChat:
            return ["Plus", "Add", "NewChat", "Create"]
        case .stopButton:
            return ["Stop", "Square", "X"]
        case .closeButton:
            return ["Close", "X", "Dismiss"]
        case .backButton:
            return ["Back", "ArrowLeft", "ChevronLeft"]
        case .menuButton:
            return ["Menu", "Hamburger", "Dots"]
        case .moreButton:
            return ["More", "DotsVertical", "Ellipsis"]
        default:
            return []
        }
    }
}

/// Result of smart element finding
struct SmartElementResult: Codable, Equatable {
    /// CSS selector that found the element
    let selector: String
    /// Confidence score (0.0 - 1.0)
    let confidence: Float
    /// How the element was found
    let method: String
    /// Classified element type
    let elementType: ElementType
    /// Element text content (if any)
    let text: String?
    /// Element aria-label (if any)
    let ariaLabel: String?
    /// Element CSS classes
    let classes: [String]
    /// Element tag name
    let tagName: String
    /// Whether element is visible
    let isVisible: Bool
    /// Whether element is enabled
    let isEnabled: Bool
    /// Element position in viewport
    let position: ElementPosition?
}

/// Element position in viewport
struct ElementPosition: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// DOM analysis result
struct DOMAnalysis: Codable, Equatable {
    let buttons: [ElementInfo]
    let inputs: [ElementInfo]
    let dropdowns: [ElementInfo]
    let links: [ElementInfo]
    let allInteractive: [ElementInfo]
}

/// Information about a single DOM element
struct ElementInfo: Codable, Equatable {
    let selector: String
    let tagName: String
    let text: String
    let ariaLabel: String
    let classes: [String]
    let isVisible: Bool
    let isEnabled: Bool
    let position: ElementPosition?
    let elementType: ElementType
    let confidence: Float
}

/// Smart element finder that classifies web UI elements by their function.
///
/// When catalog selectors fail (e.g., after a website update), this module
/// scans the DOM and identifies elements by analyzing CSS classes, aria attributes,
/// SVG icons, DOM position, and element type.
///
/// ## Usage
/// ```swift
/// let result = await SmartElementFinder.findElement(
///     bridge: bridge,
///     description: "send button",
///     context: "https://www.kimi.com/"
/// )
/// if let result = result {
///     try await bridge.click(selector: result.selector)
/// }
/// ```
///
/// ## Classification Algorithm
/// 1. Scan all interactive elements (button, a, input, textarea, div[role])
/// 2. For each element, extract: classes, aria-label, data-*, text, position
/// 3. Score each ElementType based on keyword matching
/// 4. Return the highest-confidence match above threshold (0.5)
///
/// ## Fallback Chain
/// 1. Exact CSS selector from catalog
/// 2. Smart classification by keywords
/// 3. Position-based heuristics (send button in bottom-right, etc.)
/// 4. SVG icon analysis
/// 5. Manual user intervention (captcha, login)
enum SmartElementFinder {

    /// Minimum confidence threshold for element matching
    static let confidenceThreshold: Float = 0.7

    /// Maximum number of elements to scan
    static let maxScanElements = 500

    // MARK: - Public API

    /// Find an element by natural language description.
    ///
    /// - Parameters:
    ///   - bridge: Browser automation bridge for DOM access
    ///   - description: Natural language description ("send button", "model selector")
    ///   - context: Current page URL or context string
    /// - Returns: Best matching element with confidence score, or nil if nothing found
    ///
    /// ## Flow
    /// 1. `analyzeDOM()` → get all interactive elements
    /// 2. `classifyAll()` → classify each element
    /// 3. `rankByDescription()` → rank by description match
    /// 4. Return best match above threshold
    public static func findElement(
        bridge: BrowserAutomationBridge,
        description: String,
        context: String = ""
    ) async -> SmartElementResult? {
        let analysis = await analyzeDOM(bridge: bridge)
        let descriptionLower = description.lowercased()

        var candidates: [(ElementInfo, Float)] = []

        for element in analysis.allInteractive {
            let score = scoreElement(element, against: descriptionLower)
            if score > confidenceThreshold {
                candidates.append((element, score))
            }
        }

        // Sort by confidence descending
        candidates.sort { $0.1 > $1.1 }

        guard let best = candidates.first else { return nil }

        return SmartElementResult(
            selector: best.0.selector,
            confidence: best.1,
            method: "smart-classify",
            elementType: best.0.elementType,
            text: best.0.text.isEmpty ? nil : best.0.text,
            ariaLabel: best.0.ariaLabel.isEmpty ? nil : best.0.ariaLabel,
            classes: best.0.classes,
            tagName: best.0.tagName,
            isVisible: best.0.isVisible,
            isEnabled: best.0.isEnabled,
            position: best.0.position
        )
    }

    /// Analyze the DOM and classify all interactive elements.
    ///
    /// - Parameter bridge: Browser automation bridge
    /// - Returns: DOM analysis with all interactive elements classified
    ///
    /// ## JavaScript Execution
    /// Scans for: button, a, input, textarea, [role="button"], [role="textbox"],
    /// [contenteditable], [tabindex]
    public static func analyzeDOM(bridge: BrowserAutomationBridge) async -> DOMAnalysis {
        let js = """
        (function(){
            var selectors = [
                'button', 'a[href]', 'input', 'textarea',
                '[role="button"]', '[role="textbox"]', '[role="combobox"]',
                '[role="option"]', '[role="menuitem"]',
                '[contenteditable="true"]', '[tabindex]'
            ];
            var elements = [];
            var seen = new Set();

            selectors.forEach(function(sel) {
                document.querySelectorAll(sel).forEach(function(el) {
                    if (seen.has(el) || elements.length >= \(maxScanElements)) return;
                    seen.add(el);

                    var rect = el.getBoundingClientRect();
                    var style = window.getComputedStyle(el);
                    var visible = style.display !== 'none'
                               && style.visibility !== 'hidden'
                               && style.opacity !== '0'
                               && rect.width > 0
                               && rect.height > 0;

                    var classes = (el.className && typeof el.className === 'string')
                        ? el.className.split(/\\s+/).filter(function(c){ return c.length > 0; })
                        : [];

                    var info = {
                        selector: buildSelector(el),
                        tagName: el.tagName.toLowerCase(),
                        text: (el.innerText || el.textContent || '').trim().substring(0, 100),
                        ariaLabel: el.getAttribute('aria-label') || '',
                        classes: classes,
                        isVisible: visible,
                        isEnabled: !el.disabled && el.getAttribute('aria-disabled') !== 'true',
                        position: visible ? {
                            x: Math.round(rect.x),
                            y: Math.round(rect.y),
                            width: Math.round(rect.width),
                            height: Math.round(rect.height)
                        } : null,
                        dataTestId: el.getAttribute('data-testid') || '',
                        dataTest: el.getAttribute('data-test') || '',
                        placeholder: el.getAttribute('placeholder') || '',
                        inputType: el.getAttribute('type') || '',
                        href: el.getAttribute('href') || '',
                        contentEditable: el.getAttribute('contenteditable') || '',
                        role: el.getAttribute('role') || '',
                        ariaHasPopup: el.getAttribute('aria-haspopup') || '',
                        ariaExpanded: el.getAttribute('aria-expanded') || '',
                        svgName: getSvgName(el)
                    };
                    elements.push(info);
                });
            });

            function buildSelector(el) {
                if (el.id) return '#' + el.id;
                var path = [];
                while (el && el.nodeType === 1) {
                    var selector = el.tagName.toLowerCase();
                    if (el.id) { selector = '#' + el.id; path.unshift(selector); break; }
                    if (el.className && typeof el.className === 'string' && el.className.trim()) {
                        var classes = el.className.trim().split(/\\s+/);
                        if (classes.length <= 2) {
                            selector += '.' + classes.join('.');
                        } else {
                            selector += '.' + classes[0];
                        }
                    }
                    var parent = el.parentElement;
                    if (parent) {
                        var siblings = Array.from(parent.children).filter(function(c){
                            return c.tagName === el.tagName;
                        });
                        if (siblings.length > 1) {
                            var index = siblings.indexOf(el) + 1;
                            selector += ':nth-of-type(' + index + ')';
                        }
                    }
                    path.unshift(selector);
                    el = el.parentElement;
                    if (path.length >= 4) break;
                }
                return path.join(' > ');
            }

            function getSvgName(el) {
                var svg = el.querySelector('svg');
                if (!svg) {
                    var parent = el.parentElement;
                    if (parent && parent.tagName === 'svg') svg = parent;
                }
                if (!svg) return '';
                return svg.getAttribute('name') || svg.getAttribute('data-name') || '';
            }

            return JSON.stringify(elements);
        })();
        """
        guard let json = (try? await bridge.evaluateJS(js)) as? String,
              let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return DOMAnalysis(buttons: [], inputs: [], dropdowns: [], links: [], allInteractive: [])
        }

        let elements: [ElementInfo] = raw.compactMap { dict in
            guard let selector = dict["selector"] as? String,
                  let tagName = dict["tagName"] as? String else { return nil }

            let text = dict["text"] as? String ?? ""
            let ariaLabel = dict["ariaLabel"] as? String ?? ""
            let classes = dict["classes"] as? [String] ?? []
            let isVisible = dict["isVisible"] as? Bool ?? false
            let isEnabled = dict["isEnabled"] as? Bool ?? false

            var position: ElementPosition?
            if let posDict = dict["position"] as? [String: Any],
               let x = posDict["x"] as? Double,
               let y = posDict["y"] as? Double,
               let w = posDict["width"] as? Double,
               let h = posDict["height"] as? Double {
                position = ElementPosition(x: x, y: y, width: w, height: h)
            }

            let elementType = classifyElement(
                tagName: tagName,
                classes: classes,
                ariaLabel: ariaLabel,
                text: text,
                role: dict["role"] as? String ?? "",
                ariaHasPopup: dict["ariaHasPopup"] as? String ?? "",
                inputType: dict["inputType"] as? String ?? "",
                placeholder: dict["placeholder"] as? String ?? "",
                contentEditable: dict["contentEditable"] as? String ?? "",
                svgName: dict["svgName"] as? String ?? "",
                dataTestId: dict["dataTestId"] as? String ?? "",
                position: position
            )

            let confidence = computeConfidence(
                elementType: elementType,
                tagName: tagName,
                classes: classes,
                ariaLabel: ariaLabel,
                text: text,
                svgName: dict["svgName"] as? String ?? ""
            )

            return ElementInfo(
                selector: selector,
                tagName: tagName,
                text: text,
                ariaLabel: ariaLabel,
                classes: classes,
                isVisible: isVisible,
                isEnabled: isEnabled,
                position: position,
                elementType: elementType,
                confidence: confidence
            )
        }

        let buttons = elements.filter { $0.elementType == .sendButton || $0.tagName == "button" }
        let inputs = elements.filter { $0.elementType == .input }
        let dropdowns = elements.filter { $0.elementType == .modelDropdown || $0.elementType == .effortToggle }
        let links = elements.filter { $0.tagName == "a" }

        return DOMAnalysis(
            buttons: buttons,
            inputs: inputs,
            dropdowns: dropdowns,
            links: links,
            allInteractive: elements
        )
    }

    // MARK: - Classification

    /// Classify an element by its attributes
    static func classifyElement(
        tagName: String,
        classes: [String],
        ariaLabel: String,
        text: String,
        role: String,
        ariaHasPopup: String,
        inputType: String,
        placeholder: String,
        contentEditable: String,
        svgName: String,
        dataTestId: String,
        position: ElementPosition?
    ) -> ElementType {
        let classesStr = classes.joined(separator: " ").lowercased()
        let ariaLabelLower = ariaLabel.lowercased()
        let textLower = text.lowercased()
        let dataTestIdLower = dataTestId.lowercased()

        // Score each type
        var scores: [(ElementType, Float)] = []

        for type in ElementType.allCases where type != .unknown {
            let score = scoreClassification(
                type: type,
                tagName: tagName,
                classesStr: classesStr,
                ariaLabelLower: ariaLabelLower,
                textLower: textLower,
                role: role,
                ariaHasPopup: ariaHasPopup,
                inputType: inputType,
                placeholder: placeholder,
                contentEditable: contentEditable,
                svgName: svgName,
                dataTestIdLower: dataTestIdLower,
                position: position
            )
            if score > 0 {
                scores.append((type, score))
            }
        }

        scores.sort { $0.1 > $1.1 }
        return scores.first?.0 ?? .unknown
    }

    // MARK: - Scoring

    /// Score an element against a natural language description
    private static func scoreElement(_ element: ElementInfo, against description: String) -> Float {
        var score: Float = 0

        // Direct type match
        let typeKeywords: [ElementType: [String]] = [
            .sendButton: ["send", "submit", "отправить", "отправка"],
            .input: ["input", "type", "write", "compose", "message", "ввод", "написать"],
            .modelDropdown: ["model", "select", "choose", "модель", "выбор"],
            .newChat: ["new", "create", "start", "новый", "создать", "начать"],
            .effortToggle: ["effort", "thinking", "reasoning", "размышление"],
            .stopButton: ["stop", "cancel", "остановить", "отмена"],
            .loginButton: ["login", "sign in", "войти"],
            .logoutButton: ["logout", "sign out", "выйти"],
            .profileButton: ["profile", "account", "профиль", "аккаунт"],
            .searchButton: ["search", "find", "поиск"],
            .menuButton: ["menu", "menu", "меню"],
            .settingsButton: ["settings", "config", "настройки"],
            .shareButton: ["share", "поделиться"],
            .copyButton: ["copy", "копировать"],
            .deleteButton: ["delete", "remove", "удалить"],
            .refreshButton: ["refresh", "reload", "обновить"]
        ]

        if let keywords = typeKeywords[element.elementType] {
            for keyword in keywords {
                if description.contains(keyword) {
                    score += 0.6
                    break
                }
            }
        }

        // Text match
        if !element.text.isEmpty && description.contains(element.text.lowercased()) {
            score += 0.3
        }

        // Aria-label match
        if !element.ariaLabel.isEmpty && description.contains(element.ariaLabel.lowercased()) {
            score += 0.3
        }

        // Class keyword match
        for type in ElementType.allCases where type != .unknown {
            for keyword in type.classKeywords {
                if description.contains(keyword) && element.classes.contains(where: { $0.lowercased().contains(keyword) }) {
                    score += 0.2
                }
            }
        }

        return min(score, 1.0)
    }

    /// Compute classification confidence score
    private static func computeConfidence(
        elementType: ElementType,
        tagName: String,
        classes: [String],
        ariaLabel: String,
        text: String,
        svgName: String
    ) -> Float {
        guard elementType != .unknown else { return 0 }

        var confidence: Float = 0.3 // Base confidence for classified elements

        // Tag match bonus
        let expectedTags: [ElementType: [String]] = [
            .sendButton: ["button", "div", "span"],
            .input: ["input", "textarea", "div"],
            .modelDropdown: ["button", "div", "span", "select"],
            .newChat: ["button", "a", "div"],
            .stopButton: ["button", "div"],
            .loginButton: ["button", "a"],
            .logoutButton: ["button", "a"]
        ]

        if let expected = expectedTags[elementType], expected.contains(tagName) {
            confidence += 0.2
        }

        // Class keyword match bonus
        let classStr = classes.joined(separator: " ").lowercased()
        for keyword in elementType.classKeywords {
            if classStr.contains(keyword) {
                confidence += 0.2
                break
            }
        }

        // Aria-label match bonus
        let ariaLower = ariaLabel.lowercased()
        for keyword in elementType.ariaKeywords {
            if ariaLower.contains(keyword) {
                confidence += 0.2
                break
            }
        }

        // SVG icon match bonus
        if !svgName.isEmpty {
            for icon in elementType.svgIconNames {
                if svgName.lowercased().contains(icon.lowercased()) {
                    confidence += 0.1
                    break
                }
            }
        }

        // Text content match bonus (for buttons)
        if !text.isEmpty && elementType == .sendButton {
            let sendTexts = ["send", "submit", "отправить", "→", "↑"]
            if sendTexts.contains(where: { text.lowercased().contains($0) }) {
                confidence += 0.1
            }
        }

        return min(confidence, 1.0)
    }

    /// Score classification for a specific element type
    private static func scoreClassification(
        type: ElementType,
        tagName: String,
        classesStr: String,
        ariaLabelLower: String,
        textLower: String,
        role: String,
        ariaHasPopup: String,
        inputType: String,
        placeholder: String,
        contentEditable: String,
        svgName: String,
        dataTestIdLower: String,
        position: ElementPosition?
    ) -> Float {
        var score: Float = 0

        // CSS class keywords
        for keyword in type.classKeywords {
            if classesStr.contains(keyword) {
                score += 0.3
                break
            }
        }

        // Aria-label keywords
        for keyword in type.ariaKeywords {
            if ariaLabelLower.contains(keyword) {
                score += 0.3
                break
            }
        }

        // SVG icon names
        for icon in type.svgIconNames {
            if svgName.lowercased().contains(icon.lowercased()) {
                score += 0.2
                break
            }
        }

        // Data-testid
        for keyword in type.classKeywords {
            if dataTestIdLower.contains(keyword) {
                score += 0.2
                break
            }
        }

        // Type-specific heuristics
        switch type {
        case .sendButton:
            // Send button is usually in bottom-right corner
            if let pos = position, pos.y > 400 {
                score += 0.1
            }
            // Usually small and square
            if let pos = position, pos.width > 20 && pos.width < 80 && pos.height > 20 && pos.height < 80 {
                score += 0.1
            }
            // Often has paper plane SVG
            if svgName.lowercased().contains("send") || svgName.lowercased().contains("plane") {
                score += 0.2
            }
            // Text content
            if textLower == "send" || textLower == "отправить" || textLower == "→" || textLower == "↑" {
                score += 0.2
            }
            // Negative: NOT a send button if class contains upgrade/membership/premium/pay
            let negativeKeywords = ["upgrade", "membership", "premium", "pay", "subscription", "billing", "plan", "pro", "enterprise"]
            for keyword in negativeKeywords {
                if classesStr.contains(keyword) {
                    score -= 0.5
                    break
                }
            }

        case .input:
            // Input elements
            if tagName == "input" || tagName == "textarea" {
                score += 0.2
            }
            if contentEditable == "true" {
                score += 0.2
            }
            if !placeholder.isEmpty {
                score += 0.1
            }
            if role == "textbox" {
                score += 0.2
            }

        case .modelDropdown:
            // Dropdown triggers
            if ariaHasPopup == "listbox" || ariaHasPopup == "menu" {
                score += 0.2
            }
            if role == "combobox" {
                score += 0.2
            }
            // Text often contains model name
            if textLower.contains("model") || textLower.contains("gpt") || textLower.contains("claude") {
                score += 0.1
            }

        case .newChat:
            // New chat button
            if svgName.lowercased().contains("plus") || svgName.lowercased().contains("add") {
                score += 0.2
            }
            if textLower.contains("new") || textLower.contains("новый") {
                score += 0.2
            }

        case .effortToggle:
            // Effort toggle
            if textLower.contains("effort") || textLower.contains("thinking") {
                score += 0.2
            }
            if classesStr.contains("effort") || classesStr.contains("thinking") {
                score += 0.2
            }

        case .stopButton:
            // Stop button
            if svgName.lowercased().contains("stop") || svgName.lowercased().contains("square") {
                score += 0.2
            }
            if textLower == "stop" || textLower == "остановить" {
                score += 0.2
            }

        default:
            break
        }

        return score
    }
}
