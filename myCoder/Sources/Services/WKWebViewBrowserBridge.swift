import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// Live BrowserAutomationBridge backed by a WKWebView (plan Раздел 12 Блок 3
/// п.27/п.29). Drives the vendor's web chat in-app via JavaScript: type into
/// the input, click send, read the response container, detect the stop button,
/// grab page text/URL/cookies, and screenshot for captcha display. No external
/// Playwright process — the same in-app web view used for login is reused so
/// the captured session/cookies apply.
#if canImport(WebKit)
enum WKWebViewBridgeError: LocalizedError {
    case invalidURL(String)
    case elementNotFound(String)
    case navigationTimeout

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid web provider URL: \(url)"
        case .elementNotFound(let selector): return "Web provider element not found: \(selector)"
        case .navigationTimeout: return WebBrowserTransportLogic.navigationTimeoutMessage
        }
    }
}

@MainActor
final class WKWebViewBrowserBridge: NSObject, BrowserAutomationBridge {
    let webView: WKWebView
    let selectors: WebVendorSelectors

    init(webView: WKWebView, selectors: WebVendorSelectors) {
        self.webView = webView
        self.selectors = selectors
    }

    func navigate(to url: String) async throws {
        guard let u = URL(string: url) else { throw WKWebViewBridgeError.invalidURL(url) }
        webView.load(URLRequest(url: u))
        // Wait for page to start loading
        await wait(ms: 500)
        // Wait for document readyState === 'complete'. A timeout is a
        // transport failure, not a successful navigation with a half-loaded DOM.
        for _ in 0..<30 {
            let ready = (try? await eval("document.readyState === 'complete'")) as? Bool ?? false
            if case .ready = WebBrowserTransportLogic.navigationOutcome(documentReady: ready) {
                return
            }
            await wait(ms: 500)
        }
        throw WKWebViewBridgeError.navigationTimeout
    }

    func typeText(_ text: String, into selector: String, humanized: Bool, pressEnter: Bool = true) async throws {
        // React/Vue editors do not observe a plain `value = ...` assignment.
        // Use the native setter and the same beforeinput/input/change sequence a
        // real keystroke produces, then dispatch Enter so submit handlers see a
        // background keyboard interaction without requiring an active window.
        //
        // Protocol (audit 2026-09-08): for contenteditable composers this is
        // paste-first — execCommand does not update ProseMirror/React state and
        // the vendor's own paste handler is the only verified route. The JS
        // below dispatches the paste and reports what happened; the Swift
        // side then verifies the composer content over a bounded window
        // (Kimi renders the insertion asynchronously) and only runs the
        // execCommand fallback once the paste is proven absent — so a slow
        // async paste is never duplicated and a real failure is retried.
        let escaped = Self.jsString(text)
        let js = """
        (function(){
          // Audit 2026-09-08: a multi-selector ("textarea, div.tiptap, …")
          // matched the FIRST DOM node even when it was the wrong editor
          // (live: Claude renders a decorative <textarea> AND the real
          // ProseMirror composer; querySelector picked the textarea and the
          // paste never reached the editor state). querySelectorAll returns
          // DOCUMENT order, not selector order — so the vendor's primary
          // editor class must win explicitly: pick the first VISIBLE
          // contenteditable div, and only fall back to a textarea.
          var candidates = document.querySelectorAll(\(Self.jsString(selector)));
          var el = null;
          var fallback = null;
          for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i];
            var r = c.getBoundingClientRect();
            if (r.width < 20 || r.height < 8) { continue; }
            if (!fallback && (c.tagName === 'TEXTAREA' || c.tagName === 'INPUT')) {
              fallback = c;
            } else if (c.isContentEditable) { el = c; break; }
          }
          if (!el) { el = fallback; }
          if(!el){return 'no-element';}
          el.focus();

          if (el.isContentEditable) {
            // Audit 2026-09-08 (Claude/Tiptap): execCommand('insertText')
            // writes into the DOM but the ProseMirror state stays empty, so
            // the send button never enables. A ClipboardEvent('paste') with a
            // DataTransfer goes through the vendor's REAL paste handler and
            // updates framework state.
            // Live-tested caveat (Claude): a manual selection rewrite BEFORE
            // the paste (selectNodeContents + delete) breaks ProseMirror —
            // but a paste on top of stale text APPENDS (Kimi keeps unsent
            // drafts). Clear only when the composer holds text; the editor
            // may render the deletion ASYNCHRONOUSLY (live: Kimi shows the
            // old text for hundreds of ms after delete), so the Swift side
            // verifies emptiness over a window instead of failing instantly.
            var existing = (el.innerText || '').replace(/\\u00a0/g, ' ').trim();
            if (existing.length > 0) {
              try {
                var sel = window.getSelection();
                var range = document.createRange();
                range.selectNodeContents(el);
                sel.removeAllRanges();
                sel.addRange(range);
                document.execCommand('delete');
              } catch (_) {}
              window.__mycoderClearing = \(Self.jsString(selector));
              return 'clear-pending';
            }
            try {
              var dt = new DataTransfer();
              dt.setData('text/plain', \(escaped));
              var pasteEvent = new ClipboardEvent('paste', {
                bubbles: true, cancelable: true, clipboardData: dt
              });
              // dispatchEvent returns FALSE when the vendor's paste handler
              // calls preventDefault (it inserts the text itself) — that is
              // the SUCCESS path, not a failure. Kimi renders the insertion
              // asynchronously, so content verification happens in Swift.
              el.dispatchEvent(pasteEvent);
            } catch (_) {}
            return 'pasted';
          }
          var proto = el instanceof HTMLTextAreaElement
            ? HTMLTextAreaElement.prototype
            : HTMLInputElement.prototype;
          var descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
          if (descriptor && descriptor.set) {
            descriptor.set.call(el, \(escaped));
          } else {
            el.value = \(escaped);
          }
          var inputEvent = null;
          try {
            inputEvent = new InputEvent('input', {
              bubbles: true, cancelable: false, inputType: 'insertText', data: \(escaped)
            });
          } catch (_) {
            inputEvent = new Event('input', {bubbles: true});
          }
          el.dispatchEvent(inputEvent);
          el.dispatchEvent(new Event('change', {bubbles:true}));
          return 'typed';
        })();
        """
        let outcome = (try? await eval(js)) as? String ?? "no-element"
        switch outcome {
        case "no-element":
            throw WKWebViewBridgeError.elementNotFound(selector)
        case "clear-pending":
            // Async deletion window (live: Kimi). Wait for the composer to
            // actually become empty, then run the paste stage.
            var cleared = false
            let emptinessCheck = """
            (function(){
              var candidates = document.querySelectorAll(\(Self.jsString(selector)));
              var el = null;
              var fallback = null;
              for (var i = 0; i < candidates.length; i++) {
                var c = candidates[i];
                var r = c.getBoundingClientRect();
                if (r.width < 20 || r.height < 8) { continue; }
                if (!fallback && (c.tagName === 'TEXTAREA' || c.tagName === 'INPUT')) {
                  fallback = c;
                } else if (c.isContentEditable) { el = c; break; }
              }
              if (!el) { el = fallback; }
              if (!el) { return false; }
              return ((el.innerText || '').replace(/\\u00a0/g, ' ').trim().length === 0);
            })();
            """
            for _ in 0..<WebComposerInputPolicy.verifyAttempts {
                if (try? await eval(emptinessCheck)) as? Bool == true { cleared = true; break }
                try? await Task.sleep(nanoseconds: UInt64(WebComposerInputPolicy.verifyDelayMs) * 1_000_000)
            }
            guard cleared else {
                // The editor holds text it refuses to clear (persistent
                // unsent draft). Never append on top — that corrupts it.
                throw WKWebViewBridgeError.elementNotFound("\(selector) (composer not clearable)")
            }
            let pasteJS = """
            (function(){
              var candidates = document.querySelectorAll(\(Self.jsString(selector)));
              var el = null;
              var fallback = null;
              for (var i = 0; i < candidates.length; i++) {
                var c = candidates[i];
                var r = c.getBoundingClientRect();
                if (r.width < 20 || r.height < 8) { continue; }
                if (!fallback && (c.tagName === 'TEXTAREA' || c.tagName === 'INPUT')) {
                  fallback = c;
                } else if (c.isContentEditable) { el = c; break; }
              }
              if (!el) { el = fallback; }
              if (!el) { return false; }
              el.focus();
              try {
                var dt = new DataTransfer();
                dt.setData('text/plain', \(escaped));
                el.dispatchEvent(new ClipboardEvent('paste', {
                  bubbles: true, cancelable: true, clipboardData: dt
                }));
              } catch (_) {}
              return true;
            })();
            """
            _ = try? await eval(pasteJS)
            try await verifyPasteOrFallback(escaped: escaped, selector: selector)
        case "typed":
            // Audit 2026-09-09 (Qwen live): the native-setter + synthetic
            // InputEvent write can silently miss React state (hydration race
            // on a fresh page) — the composer stays empty, the send button
            // stays disabled, and the later click fails with a misleading
            // "element not found". Verify the text landed; retry once via
            // focus + execCommand before failing loudly.
            try await verifyTypedOrRetry(escaped: escaped, selector: selector)
        case "pasted":
            try await verifyPasteOrFallback(escaped: escaped, selector: selector)
        default:
            throw WKWebViewBridgeError.elementNotFound(selector)
        }

        // Enter is requested only for the non-paste path (button-driven sends
        // pass pressEnter=false; on qwen.ai a synthetic Enter CLEARS the input).
        guard pressEnter else { return }
        let enterJS = """
        (function(){
          var candidates = document.querySelectorAll(\(Self.jsString(selector)));
          var el = null;
          for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i];
            var r = c.getBoundingClientRect();
            if (r.width >= 20 && r.height >= 8) { el = c; break; }
          }
          if (!el) { return false; }
          var keyOptions = {key:'Enter', code:'Enter', keyCode:13, which:13,
                            bubbles:true, cancelable:true};
          try { el.dispatchEvent(new KeyboardEvent('keydown', keyOptions)); } catch (_) {}
          try { el.dispatchEvent(new KeyboardEvent('keypress', keyOptions)); } catch (_) {}
          try { el.dispatchEvent(new KeyboardEvent('keyup', keyOptions)); } catch (_) {}
          return true;
        })();
        """
        guard (try? await eval(enterJS)) as? Bool == true else {
            throw WKWebViewBridgeError.elementNotFound(selector)
        }
    }

    /// Stage 2 of the paste protocol (audit 2026-09-08): after the paste is
    /// dispatched, wait for the composer to actually contain the text (Kimi
    /// renders asynchronously, ~300 ms). If it never lands, run the
    /// execCommand/DOM fallback once and verify again. This keeps a slow
    /// async paste from being duplicated and a real failure surfaced.
    private func verifyPasteOrFallback(escaped: String, selector: String) async throws {
        let contentCheck = """
        (function(){
          var candidates = document.querySelectorAll(\(Self.jsString(selector)));
          var el = null;
          var fallback = null;
          for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i];
            var r = c.getBoundingClientRect();
            if (r.width < 20 || r.height < 8) { continue; }
            if (!fallback && (c.tagName === 'TEXTAREA' || c.tagName === 'INPUT')) {
              fallback = c;
            } else if (c.isContentEditable) { el = c; break; }
          }
          if (!el) { el = fallback; }
          if (!el) { return false; }
          return ((el.innerText || '') + '\\n').indexOf(\(escaped)) !== -1;
        })();
        """
        for _ in 0..<WebComposerInputPolicy.verifyAttempts {
            if (try? await eval(contentCheck)) as? Bool == true { return }
            try? await Task.sleep(nanoseconds: UInt64(WebComposerInputPolicy.verifyDelayMs) * 1_000_000)
        }
        // Paste not rendered within the window: last-resort execCommand +
        // DOM write, then verify once more. Firing it earlier risked
        // duplicating a still-in-flight async paste (live: Kimi).
        let fallbackJS = """
        (function(){
          var candidates = document.querySelectorAll(\(Self.jsString(selector)));
          var el = null;
          var fallback = null;
          for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i];
            var r = c.getBoundingClientRect();
            if (r.width < 20 || r.height < 8) { continue; }
            if (!fallback && (c.tagName === 'TEXTAREA' || c.tagName === 'INPUT')) {
              fallback = c;
            } else if (c.isContentEditable) { el = c; break; }
          }
          if (!el) { el = fallback; }
          if (!el) { return false; }
          el.focus();
          var ok = false;
          try { ok = document.execCommand('insertText', false, \(escaped)); } catch (_) {}
          if (!ok) {
            el.textContent = \(escaped);
            el.dispatchEvent(new Event('input', {bubbles: true}));
            ok = true;
          }
          return ok;
        })();
        """
        guard (try? await eval(fallbackJS)) as? Bool == true else {
            throw WKWebViewBridgeError.elementNotFound(selector)
        }
    }

    /// Verify a native-setter textarea write actually landed in the composer
    /// (audit 2026-09-09, Qwen): React-controlled inputs can swallow the
    /// synthetic InputEvent on a hydrating page. Poll briefly, then retry
    /// once via focus + execCommand('insertText'), then fail loudly — never
    /// report success with an empty composer (that cascades into a disabled
    /// send button and a misleading "element not found" click error).
    private func verifyTypedOrRetry(escaped: String, selector: String) async throws {
        let contentCheck = """
        (function(){
          var candidates = document.querySelectorAll(\(Self.jsString(selector)));
          for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i];
            var r = c.getBoundingClientRect();
            if (r.width < 20 || r.height < 8) { continue; }
            var v = (c.value !== undefined) ? String(c.value) : String(c.innerText || '');
            if ((v + '\\n').indexOf(\(escaped)) !== -1) { return true; }
          }
          return false;
        })();
        """
        for _ in 0..<WebComposerInputPolicy.verifyAttempts {
            if (try? await eval(contentCheck)) as? Bool == true { return }
            try? await Task.sleep(nanoseconds: UInt64(WebComposerInputPolicy.verifyDelayMs) * 1_000_000)
        }
        let retryJS = """
        (function(){
          var candidates = document.querySelectorAll(\(Self.jsString(selector)));
          var el = null;
          for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i];
            var r = c.getBoundingClientRect();
            if (r.width >= 20 && r.height >= 8) { el = c; break; }
          }
          if (!el) { return false; }
          el.focus();
          try {
            if (document.execCommand('insertText', false, \(escaped))) { return true; }
          } catch (_) {}
          try {
            var proto = el instanceof HTMLTextAreaElement
              ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            var desc = Object.getOwnPropertyDescriptor(proto, 'value');
            if (desc && desc.set) { desc.set.call(el, \(escaped)); }
            else { el.value = \(escaped); }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return true;
          } catch (_) { return false; }
        })();
        """
        _ = try? await eval(retryJS)
        for _ in 0..<WebComposerInputPolicy.verifyAttempts {
            if (try? await eval(contentCheck)) as? Bool == true { return }
            try? await Task.sleep(nanoseconds: UInt64(WebComposerInputPolicy.verifyDelayMs) * 1_000_000)
        }
        throw WKWebViewBridgeError.elementNotFound("\(selector) (typed text never landed in the composer)")
    }

    func click(selector: String) async throws {
        // Support :has-text() pseudo-class for text-based matching
        if let text = extractHasText(from: selector) {
            let js = """
            (function(){
              var wanted = \(Self.jsString(text));
              var all = document.querySelectorAll('button, a, div, span, li');
              for (var i = 0; i < all.length; i++) {
                var t = (all[i].innerText || all[i].textContent || '').trim();
                if (t === wanted || t.indexOf(wanted) !== -1) {
                  all[i].click();
                  return true;
                }
              }
              return false;
            })();
            """
            guard (try await eval(js) as? Bool) == true else {
                throw WKWebViewBridgeError.elementNotFound(selector)
            }
            return
        }
        let js = """
        (function(){
          var el = document.querySelector(\(Self.jsString(selector)));
          if(!el){return 'missing';}
          var target = el.matches('button, [role="button"], input[type="submit"]')
            ? el
            : (el.querySelector('button, [role="button"], input[type="submit"]') || el);
          if (target.disabled || target.getAttribute('aria-disabled') === 'true') { return 'disabled'; }
          // Audit 2026-09-06 (Claude/Radix): a full pointer event cycle
          // (pointerdown→mousedown→pointerup→mouseup→click) DOUBLE-TOGGLES
          // Radix popper menus — they treat the extra synthetic mouseups as
          // second clicks and immediately close. The empirically verified
          // open sequence on the live page is focus() + click(): React
          // receives one click from a focused document and the menu stays
          // open. Non-Radix sites ignore focus and behave the same.
          try { target.focus(); } catch (_) {}
          target.click();
          return 'clicked';
        })();
        """
        // Audit 2026-09-09 (Qwen live): a DISABLED send button (empty
        // composer — typing never landed) used to surface as a generic
        // "element not found", hiding the real cause. Report it distinctly.
        let outcome = (try? await eval(js)) as? String ?? "missing"
        switch outcome {
        case "clicked":
            return
        case "disabled":
            throw WKWebViewBridgeError.elementNotFound("\(selector) (button present but disabled — the composer is empty, typing did not land)")
        default:
            throw WKWebViewBridgeError.elementNotFound(selector)
        }
    }

    func exists(selector: String) async throws -> Bool {
        // Support :has-text() pseudo-class for text-based matching
        if let text = extractHasText(from: selector) {
            let js = """
            (function(){
              var wanted = \(Self.jsString(text));
              var all = document.querySelectorAll('button, a, div, span, li');
              for (var i = 0; i < all.length; i++) {
                var t = (all[i].innerText || all[i].textContent || '').trim();
                if (t === wanted || t.indexOf(wanted) !== -1) {
                  return true;
                }
              }
              return false;
            })();
            """
            return (try? await eval(js)) as? Bool ?? false
        }
        let js = "!!document.querySelector(\(Self.jsString(selector)));"
        return (try? await eval(js)) as? Bool ?? false
    }

    /// Extract text content from `:has-text('...')` pseudo-class
    private func extractHasText(from selector: String) -> String? {
        guard selector.contains(":has-text(") else { return nil }
        // Match :has-text('text') or :has-text("text")
        let pattern = ":has-text\\(['\"]([^'\"]+)['\"]\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: selector, range: NSRange(selector.startIndex..., in: selector)),
              let range = Range(match.range(at: 1), in: selector) else { return nil }
        return String(selector[range])
    }

    /// Click the first element matching `selector` whose visible text contains
    /// (or exactly matches) `text`. Uses fuzzy matching: case-insensitive,
    /// normalized (spaces/hyphens/dots removed) comparison for robust model matching.
    @discardableResult
    func clickByText(selector: String, text: String) async throws -> Bool {
        let escaped = Self.jsString(text)
        let js = """
        (function(){
          var wanted = \(escaped);
          var wantedNorm = wanted.toLowerCase().replace(/[\\s\\-\\.\\.]/g,'');
          var els = document.querySelectorAll(\(Self.jsString(selector)));
          // 1) Exact match (case-insensitive)
          for(var i=0;i<els.length;i++){
            var t=(els[i].innerText||els[i].textContent||'').trim();
            if(t.toLowerCase()===wanted.toLowerCase()){els[i].click();return true;}
          }
          // 2) Contains match (case-insensitive)
          for(var i=0;i<els.length;i++){
            var t=(els[i].innerText||els[i].textContent||'').trim();
            var tLow = t.toLowerCase();
            if(tLow.indexOf(wanted.toLowerCase())!==-1 || wanted.toLowerCase().indexOf(tLow)!==-1){
              els[i].click();return true;
            }
          }
          // 3) Normalized fuzzy match (spaces/hyphens/dots ignored)
          for(var i=0;i<els.length;i++){
            var t=(els[i].innerText||els[i].textContent||'').trim();
            var tNorm = t.toLowerCase().replace(/[\\s\\-\\.\\.]/g,'');
            if(tNorm.indexOf(wantedNorm)!==-1 || wantedNorm.indexOf(tNorm)!==-1){
              els[i].click();return true;
            }
          }
          return false;
        })();
        """
        return (try? await eval(js)) as? Bool ?? false
    }

    func clickByTextExact(selector: String, text: String) async throws -> Bool {
        let js = """
        (function(){
          var wanted = \(Self.jsString(text));
          var els = document.querySelectorAll(\(Self.jsString(selector)));
          for(var i=0;i<els.length;i++){
            var t=(els[i].innerText||els[i].textContent||'').trim();
            if(t===wanted){els[i].click();return true;}
          }
          return false;
        })();
        """
        return (try? await eval(js)) as? Bool ?? false
    }

    @discardableResult
    func clickVisibleTextExact(selector: String, text: String) async throws -> Bool {
        let js = """
        (function(){
          var wanted = String(\(Self.jsString(text))).trim().toLowerCase().replace(/\\s+/g,' ');
          var els = document.querySelectorAll(\(Self.jsString(selector)));
          function visible(el){
            var style = window.getComputedStyle(el);
            return style.display !== 'none' && style.visibility !== 'hidden';
          }
          function norm(el){
            return String(el.innerText || el.textContent || '').trim().toLowerCase().replace(/\\s+/g,' ');
          }
          function clickThrough(el){
            var target = el.closest('[role="option"], [role="menuitem"], button, a, [tabindex]') || el;
            target.click();
          }
          var i, el;
          // Pass 1: exact normalized equality.
          for (i = 0; i < els.length; i++) {
            el = els[i];
            if (!visible(el)) { continue; }
            if (norm(el) === wanted) { clickThrough(el); return true; }
          }
          // Round 30 pass 2: vendor menus often render "Name<description>"
          // inside ONE option element ("Qwen3.7-Plus The high-performance…"),
          // which broke exact matching. Accept a prefix ONLY when the next
          // character is a space, so "…Plus-Max" can never satisfy "…Plus".
          for (i = 0; i < els.length; i++) {
            el = els[i];
            if (!visible(el)) { continue; }
            var actual = norm(el);
            if (actual.length > wanted.length &&
                actual.charAt(wanted.length) === ' ' &&
                actual.lastIndexOf(wanted, 0) === 0) {
              clickThrough(el);
              return true;
            }
          }
          return false;
        })();
        """
        return (try? await eval(js)) as? Bool ?? false
    }

    func readText(selector: String) async throws -> String {
        // Audit 2026-09-09 (ChatGPT live): in a background (never displayed)
        // WKWebView React streams the answer into the DOM but the text nodes
        // stay UNRENDERED — innerText returns "" (layout never runs) even
        // though the answer is committed (data-end markers) and visible
        // after a page reload. Force a synchronous layout (offsetHeight
        // read) and fall back to textContent so a finished-but-unrendered
        // answer is still read instead of timing out after 600 polls.
        // Audit 2026-09-09 (Qwen live): vendor ERROR placeholders
        // (div.response-message-empty — "The current content is empty, please
        // regenerate.") are visible non-empty elements that must NEVER be
        // read as the answer; they are skipped by class here (the single
        // source of truth is WebVendorErrorPlaceholderLogic).
        let errorClasses = (try? JSONSerialization.data(
            withJSONObject: WebVendorErrorPlaceholderLogic.errorClassFragments
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let js = """
        (function(){
          var errorFragments = \(errorClasses);
          function isErrorEl(el){
            var cls = String((el.className && el.className.toString()) || '').toLowerCase();
            for (var k = 0; k < errorFragments.length; k++) {
              if (cls.indexOf(String(errorFragments[k]).toLowerCase()) !== -1) { return true; }
            }
            return false;
          }
          var els = document.querySelectorAll(\(Self.jsString(selector)));
          if(!els || els.length===0){return "";}
          for (var i = els.length - 1; i >= 0; i--) {
            var el = els[i];
            if (isErrorEl(el)) { continue; }
            var style = window.getComputedStyle(el);
            if (style.display === 'none' && style.visibility === 'hidden') { continue; }
            var text = String(el.innerText || '').trim();
            if (!text) {
              try { void el.offsetHeight; } catch (_) {}
              text = String(el.innerText || '').trim();
            }
            if (!text) { text = String(el.textContent || '').trim(); }
            if (text) { return text; }
          }
          return "";
        })();
        """
        return (try? await eval(js)) as? String ?? ""
    }

    func responseFingerprint(selector: String) async throws -> String {
        // Same forced-layout/textContent contract as readText (audit
        // 2026-09-09): an unrendered-but-committed answer must still
        // produce a fingerprint, otherwise awaitResponse treats the whole
        // turn as "nothing changed" and times out on a real answer.
        let js = """
        (function(){
          var els = document.querySelectorAll(\(Self.jsString(selector)));
          if(!els || els.length===0){return "";}
          var visible = [];
          for (var i = 0; i < els.length; i++) {
            var el = els[i];
            var style = window.getComputedStyle(el);
            if (style.display !== 'none' && style.visibility !== 'hidden') {
              visible.push(el);
            }
          }
          if (!visible.length) { return ""; }
          var last = visible[visible.length - 1];
          var markup = String(last.outerHTML || last.textContent || '');
          if (markup.length < 40) {
            try { void last.offsetHeight; } catch (_) {}
            markup = String(last.outerHTML || last.textContent || '');
          }
          return String(visible.length) + ':' + markup.length + ':' + markup.slice(-1200);
        })();
        """
        return (try? await eval(js)) as? String ?? ""
    }

    /// Wait for a selector to appear in the DOM (up to timeoutMs).
    func waitForSelector(selector: String, timeout: Int = 5000) async throws {
        let deadline = Date().addingTimeInterval(Double(timeout) / 1000.0)
        while Date() < deadline {
            if (try? await exists(selector: selector)) == true { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// Read model names from a custom dropdown using a vendor-specific selector.
    /// Falls back to universal selectors if the vendor-specific one finds nothing.
    func readModelItems(modelItemSelector: String = "div.model-item") async throws -> [String] {
        let escaped = Self.jsString(modelItemSelector)
        let js = """
        (function(){
          var items = document.querySelectorAll(\(escaped));
          var result = [];
          for (var i = 0; i < items.length; i++) {
            // Use innerText (respects CSS display) instead of textContent
            // to avoid picking up hidden description text.
            var t = (items[i].innerText || items[i].textContent || '').trim();
            if (t && t.length > 0 && t.length < 60) { result.push(t); }
          }
          if (result.length > 0) { return JSON.stringify(result); }
          // Fallback: try universal selectors — use innerText and strict length filter
          var fallbacks = ['[role="option"]', '[class*="option"]', 'li'];
          for (var f = 0; f < fallbacks.length; f++) {
            var fb = document.querySelectorAll(fallbacks[f]);
            for (var j = 0; j < fb.length; j++) {
              var ft = (fb[j].innerText || fb[j].textContent || '').trim();
              // Only include short texts (model names are short, descriptions are long)
              if (ft && ft.length > 2 && ft.length < 50) { result.push(ft); }
            }
            if (result.length > 0) { break; }
          }
          return JSON.stringify(result);
        })();
        """
        guard let json = (try? await eval(js)) as? String,
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return arr
    }

    func readModelCandidates(modelItemSelector: String) async throws -> [WebModelDOMItem] {
        let selector = Self.jsString(modelItemSelector)
        // Audit 2026-09-06 (Claude live menu): a menu item's innerText packs
        // the model name, tier, description AND action into one multiline
        // string ("Fable 5.1\nPro or Max\nFor your toughest challenges\nUpgrade").
        // The MODEL LABEL is the first non-empty line — feeding the full blob
        // through the validator rejects every real model.
        let js = """
        (function(){
          var els = document.querySelectorAll(\(selector));
          var result = [];
          for (var i = 0; i < els.length; i++) {
            var el = els[i];
            var style = window.getComputedStyle(el);
            var rect = el.getBoundingClientRect();
            var visible = style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
            var rawText = String(el.innerText || el.textContent || '').trim();
            var label = rawText.split(/\\n/).map(function(s){return s.trim();}).filter(Boolean)[0] || '';
            label = label.replace(/\\s+/g, ' ');
            var parent = el.closest('[role="option"], [role="menuitem"], button, a, li, [class*="model-item"], [class*="option"]');
            var role = String(el.getAttribute('role') || (parent && parent.getAttribute('role')) || '').toLowerCase();
            var tag = String(el.tagName || '').toLowerCase();
            var parentTag = String(parent && parent.tagName || '').toLowerCase();
            var cls = String((el.className && el.className.toString()) || '') + ' ' + String((parent && parent.className && parent.className.toString()) || '');
            var selectable = role === 'option' || role === 'menuitem' || tag === 'button' || tag === 'option' || parentTag === 'button' || parentTag === 'a' || parentTag === 'li' || /model-item|model-option|option|model-selector/i.test(cls);
            var nestedOptions = el.querySelectorAll('[role="option"], [role="menuitem"], [class*="model-item"]');
            var leaf = nestedOptions.length === 0;
            var disabled = el.hasAttribute('disabled') || el.getAttribute('aria-disabled') === 'true' || (parent && (parent.hasAttribute('disabled') || parent.getAttribute('aria-disabled') === 'true'));
            var key = el.getAttribute('data-model-id') || el.getAttribute('data-id') || el.getAttribute('aria-label') || (parent && (parent.getAttribute('data-model-id') || parent.getAttribute('data-id') || parent.getAttribute('aria-label'))) || (label + '|' + cls.trim());
            if (label && label.length <= 100) {
              result.push({label: label, identity: String(key), isVisible: visible, isSelectable: selectable, isDisabled: disabled, isLeaf: leaf, sourceSelector: \(selector), fullText: rawText.substring(0, 200)});
            }
          }
          return JSON.stringify(result);
        })();
        """
        guard let json = (try? await eval(js)) as? String,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WebModelDOMItem].self, from: data)) ?? []
    }

    func readVisibleModelCandidates() async throws -> [WebModelDOMItem] {
        // Audit 2026-09-06: scan ONLY genuinely OPEN menu surfaces — an
        // element that is a popover/dropdown IN THE OPEN STATE (data-state
        // open, aria-expanded parent, role listbox/menu not inside <nav>, or
        // radix/popper content). The previous broad roots
        // ([class*="menu"]) swept up the entire ChatGPT sidebar and let chat
        // HISTORY TITLES like "Лимиты ChatGPT Pro для кодинга" be reported
        // as "models". The sidebar nav is explicitly excluded.
        let js = """
        (function(){
          const visible = el => {
            const style = window.getComputedStyle(el), rect = el.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
          };
          const inSidebar = el => !!el.closest('nav, aside, [data-testid="chat-history"], [aria-label*="Истории"], [aria-label*="History" i]');
          const openSurface = el => {
            if (inSidebar(el)) return false;
            const state = String(el.getAttribute('data-state') || '').toLowerCase();
            if (state === 'open') return true;
            const expanded = el.getAttribute && el.getAttribute('aria-expanded');
            return String(expanded).toLowerCase() === 'true';
          };
          const surfaceSelector = '[role="listbox"][data-state="open"], [role="menu"][data-state="open"], ' +
            '[role="listbox"], [role="menu"], [data-radix-popper-content], [data-radix-popper-content-wrapper], ' +
            '[class*="popover"][data-state="open"], [class*="dropdown"][data-state="open"], ' +
            '[class*="model-selector"], [class*="model-list"], [class*="wms-list"]';
          const roots = Array.from(document.querySelectorAll(surfaceSelector))
            .filter(visible)
            .filter(el => openSurface(el) || el.getAttribute('role') === 'listbox' || el.getAttribute('role') === 'menu' || el.hasAttribute('data-radix-popper-content'));
          const nodes = [];
          roots.forEach(root => {
            nodes.push(root);
            root.querySelectorAll('*').forEach(el => { if (visible(el) && !inSidebar(el)) nodes.push(el); });
          });
          const result = [];
          const seen = new Set();
          nodes.forEach(el => {
            const role = String(el.getAttribute('role') || '').toLowerCase();
            const cls = String((el.className && el.className.toString()) || '');
            const selectable = role === 'option' || role === 'menuitem' ||
              el.tagName.toLowerCase() === 'button' || el.tagName.toLowerCase() === 'a' ||
              /model-item|model-option|select/i.test(cls) ||
              el.hasAttribute('data-model-id');
            if (!selectable) return;
            const raw = String(el.getAttribute('aria-label') || el.innerText || el.textContent || '');
            const label = raw.split(/\\n/).map(s => s.trim()).filter(Boolean)[0] || '';
            if (!label || label.length > 100) return;
            const nested = el.querySelector('[role="option"], [role="menuitem"], [class*="model-item"], [class*="model-option"]');
            const identity = el.getAttribute('data-model-id') || el.getAttribute('data-id') ||
              el.getAttribute('aria-label') || label + '|' + cls;
            const key = String(identity) + '|' + label;
            if (seen.has(key)) return;
            seen.add(key);
            result.push({
              label: label,
              identity: String(identity),
              isVisible: true,
              isSelectable: true,
              isDisabled: el.hasAttribute('disabled') || el.getAttribute('aria-disabled') === 'true',
              isLeaf: !nested,
              sourceSelector: 'open-surface-scan',
              fullText: String(el.innerText || '').substring(0, 200)
            });
          });
          return JSON.stringify(result);
        })();
        """
        guard let json = (try? await eval(js)) as? String,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WebModelDOMItem].self, from: data)) ?? []
    }

    func evaluateJS(_ script: String) async throws -> Any? {
        try await eval(script)
    }

    /// Attach an image to the chat composer via a synthetic paste event with
    /// a DataTransfer file — the same code path a manual Cmd+V uses, so every
    /// vendor's own upload handler (file input, preview chip, OCR/vision
    /// pipeline) receives a REAL image without vendor-specific selectors.
    func attachImageToComposer(data: Data, mime: String) async throws -> Bool {
        let b64 = data.base64EncodedString()
        let js = """
        (function(){
          function base64ToBlob(b64, mime) {
            var bin = atob(b64);
            var bytes = new Uint8Array(bin.length);
            for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
            return new Blob([bytes], {type: mime});
          }
          var composer = document.querySelector("#prompt-textarea, div[contenteditable='true'], div.ProseMirror, textarea");
          if (!composer) return false;
          var target = composer;
          var blob = base64ToBlob(\(Self.jsString(b64)), \(Self.jsString(mime)));
          var file = new File([blob], "image.png", {type: mime});
          var dt = new DataTransfer();
          dt.items.add(file);
          var pasteEvent = new ClipboardEvent('paste', {
            bubbles: true, cancelable: true, clipboardData: dt
          });
          target.dispatchEvent(pasteEvent);
          // Also fire a drop event for composers that only listen to drops.
          var dropEvent = new DragEvent('drop', {
            bubbles: true, cancelable: true, dataTransfer: dt
          });
          target.dispatchEvent(dropEvent);
          return true;
        })();
        """
        let result = try await eval(js)
        return (result as? Bool) ?? false
    }

    func pageText() async throws -> String {
        (try? await eval("document.body ? document.body.innerText : '';")) as? String ?? ""
    }

    func currentURL() async throws -> String {
        webView.url?.absoluteString ?? ""
    }

    func cookies() async throws -> [BrowserCookie] {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return cookies.map {
            BrowserCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path,
                          expiresEpoch: $0.expiresDate?.timeIntervalSince1970,
                          httpOnly: $0.isHTTPOnly, secure: $0.isSecure)
        }
    }

    func setCookies(_ cookies: [BrowserCookie]) async throws {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for c in cookies {
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: c.name, .value: c.value, .domain: c.domain, .path: c.path
            ]
            let attributes = WebCookieRestoreLogic.attributes(for: c)
            if attributes.secure { props[.secure] = "TRUE" }
            if attributes.httpOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let exp = c.expiresEpoch { props[.expires] = Date(timeIntervalSince1970: exp) }
            if let cookie = HTTPCookie(properties: props) {
                await store.setCookie(cookie)
            }
        }
    }

    func setLocalStorage(_ values: [String: String]) async throws {
        guard !values.isEmpty else { return }
        for (key, value) in values {
            let script = "localStorage.setItem(\(Self.jsString(key)), \(Self.jsString(value))); true;"
            guard (try await eval(script) as? Bool) == true else {
                throw WKWebViewBridgeError.elementNotFound("localStorage")
            }
        }
    }

    func screenshot(selector: String?) async throws -> Data {
        await withCheckedContinuation { cont in
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { image, _ in
                #if canImport(AppKit)
                if let image = image,
                   let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    cont.resume(returning: png)
                    return
                }
                #endif
                cont.resume(returning: Data())
            }
        }
    }

    func stopGeneration() async throws {
        let selectors = [
            self.selectors.stopButton,
            "button[data-testid='stop-button']",
            "button[aria-label*='stop' i]",
            "button[aria-label*='停止']",
            "button[class*='stop' i]"
        ].filter { !$0.isEmpty }
        for selector in selectors {
            if (try? await exists(selector: selector)) == true {
                try await click(selector: selector)
                return
            }
        }
        // Some providers expose no stable stop button but still accept Escape.
        _ = try? await eval("document.activeElement && document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true})); true;")
    }

    func wait(ms: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    // MARK: - Helpers

    private func eval(_ js: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(js) { result, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume(returning: result) }
            }
        }
    }

    /// JSON-encode a string for safe embedding in JS. Pure (no actor
    /// state) so it stays callable off the main actor (FallbackRouter
    /// builds probe scripts from background tasks).
    nonisolated static func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())  // "..." from ["..."]
    }
}
#endif
