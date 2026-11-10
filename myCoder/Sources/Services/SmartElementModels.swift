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
