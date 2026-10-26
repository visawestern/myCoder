import Testing
import Foundation
@testable import myCoder

/// Round 30 — maximally permissive embedded-browser policy (user report:
/// kimi.com asks to hand off to kimi.ai and the embedded webview appeared to
/// forbid it; root cause: no WKUIDelegate, so window.open / target=_blank
/// popups were silently dropped, and JS dialogs could hang the page).
@Suite("Round 30 — WebPopupPolicy pure decisions")
struct WebPopupPolicyTests {

    @Test("popup with a real URL loads in the same view")
    func popupLoadsInPlace() {
        let action = WebPopupPolicy.popupAction(requestURL: "https://www.kimi.ai/chat?next=1")
        #expect(action == .loadInPlace("https://www.kimi.ai/chat?next=1"))
    }

    @Test("cross-vendor popup also loads in place — no host allowlist")
    func crossHostPopupAllowed() {
        let action = WebPopupPolicy.popupAction(requestURL: "https://other-vendor.example.org/login")
        #expect(action == .loadInPlace("https://other-vendor.example.org/login"))
    }

    @Test("non-http schemes are allowed in place as well")
    func arbitrarySchemeAllowed() {
        let action = WebPopupPolicy.popupAction(requestURL: "about:blank")
        #expect(action == .loadInPlace("about:blank"))
    }

    @Test("nil or empty URL adopts a new view instead of dropping the popup")
    func missingURLAdoptsNewView() {
        #expect(WebPopupPolicy.popupAction(requestURL: nil) == .adoptNewView)
        #expect(WebPopupPolicy.popupAction(requestURL: "") == .adoptNewView)
        #expect(WebPopupPolicy.popupAction(requestURL: "   ") == .adoptNewView)
    }

    @Test("URL without scheme cannot navigate — adopt new view")
    func schemelessURLAdoptsNewView() {
        #expect(WebPopupPolicy.popupAction(requestURL: "not-a-url") == .adoptNewView)
    }

    @Test("JS prompt auto-answers with the page-provided default text")
    func promptUsesDefault() {
        #expect(WebPopupPolicy.promptResponse(defaultText: "prefilled") == "prefilled")
        #expect(WebPopupPolicy.promptResponse(defaultText: nil) == "")
    }

    // MARK: - OAuth popups open in a VISIBLE window (audit 2026-09-06)
    // Live evidence: kimi.ai "Continue with Google" opens window.open to
    // accounts.google.com — in-place loading wiped the vendor page, and an
    // unattached adopted view left the user with nothing to click.

    @Test("Google OAuth popup opens in a window, never in place")
    func googleOAuthShowsInWindow() {
        let url = "https://accounts.google.com/o/oauth2/v2/auth?client_id=x"
        let action = WebPopupPolicy.popupAction(requestURL: url)
        #expect(action == .showInWindow(url))
    }

    @Test("Apple and Microsoft identity popups open in a window")
    func otherOAuthProvidersShowInWindow() {
        #expect(WebPopupPolicy.popupAction(requestURL: "https://appleid.apple.com/auth") == .showInWindow("https://appleid.apple.com/auth"))
        #expect(WebPopupPolicy.popupAction(requestURL: "https://login.microsoftonline.com/x") == .showInWindow("https://login.microsoftonline.com/x"))
    }

    @Test("OAuth detection matches subdomains and rejects ordinary sites")
    func oauthHostMatching() {
        #expect(WebPopupPolicy.isOAuthURL("https://tenant.auth0.com/authorize"))
        #expect(!WebPopupPolicy.isOAuthURL("https://www.kimi.ai/"))          // vendor page, not identity
        #expect(!WebPopupPolicy.isOAuthURL("https://chatgpt.com/"))
        #expect(!WebPopupPolicy.isOAuthURL(nil))
    }
}
