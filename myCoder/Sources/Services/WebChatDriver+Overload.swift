import Foundation

extension WebChatDriver {
    /// Dismiss a transient Kimi overload modal ("Слишком много людей" with a
    /// Понятно/Understood button) WITHOUT navigating or switching models —
    /// the session stays exactly as it is and the turn retries after a wait.
    func dismissOverloadModal() async {
        let dismissJS = """
        (function(){
          function isVisible(el) {
            var r = el.getBoundingClientRect();
            var s = window.getComputedStyle(el);
            return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
          }
          // Close/X buttons first (language-independent).
          var closeSels = ['[aria-label="Close"]', '[aria-label="Закрыть"]', '[aria-label="关闭"]',
                           '.modal-close', '.dialog-close', 'button[class*="close"]'];
          for (var s = 0; s < closeSels.length; s++) {
            var cands = document.querySelectorAll(closeSels[s]);
            for (var ci = 0; ci < cands.length; ci++) {
              if (isVisible(cands[ci])) { cands[ci].click(); return true; }
            }
          }
          // Dismiss buttons by text (RU/EN/ZH).
          var labels = ['понятно','понял','understood','got it','ok','okay','close','закрыть',
                        '知道了','明白了','好的','确定','关闭'];
          var els = document.querySelectorAll('button, [role="button"]');
          for (var i = 0; i < els.length; i++) {
            if (!isVisible(els[i])) continue;
            var t = ((els[i].innerText || els[i].textContent) || '').trim().toLowerCase();
            if (!t || t.length > 30) continue;
            for (var j = 0; j < labels.length; j++) {
              if (t === labels[j]) { els[i].click(); return true; }
            }
          }
          // Backdrop click, then Escape.
          var masks = document.querySelectorAll('.modal-mask, [class*="backdrop"], [class*="modal-overlay"]');
          for (var k = 0; k < masks.length; k++) {
            if (isVisible(masks[k])) { masks[k].click(); return true; }
          }
          document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', keyCode: 27, bubbles: true}));
          return false;
        })()
        """
        _ = try? await bridge.evaluateJS(dismissJS) as? Bool
    }

    /// Switch Kimi to the "Быстрый" (Fast) model when K3/K3 Swarm quota is
    /// exhausted. Navigates to a fresh Kimi page, dismisses any paywall modal,
    /// and selects the Fast model from the model menu. Returns true if the
    /// switch succeeded.
    func switchToFastModel(emit: (WebChatEvent) -> Void) async -> Bool {
        // Navigate to a completely fresh Kimi page to clear any modals/state.
        MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: navigating to fresh kimi.ai")
        try? await bridge.navigate(to: "https://www.kimi.ai/")
        await bridge.wait(ms: 2000)

        // Dismiss any paywall/quota/overload modal that may be blocking the
        // interface (Kimi K3 overload shows a FULLSCREEN dialog, e.g.
        // "Слишком много людей" / "too many people").
        // Strategy: (1) remove modal DOM elements, (2) close/X buttons
        // (language-independent), (3) dismiss buttons by text in RU/EN/ZH,
        // (4) backdrop click, (5) Escape, (6) CSS guard against re-appearance.
        let removeModalJS = """
        (function(){
          var removed = false;
          // Remove known modal containers (Kimi paywall "Слишком много людей", etc.)
          var modals = document.querySelectorAll(
            '[class*="modal"], [class*="Modal"], [class*="paywall"], [class*="Paywall"], ' +
            '[class*="dialog"], [class*="Dialog"], [role="dialog"], [role="alertdialog"]'
          );
          modals.forEach(function(m) {
            // Only remove if it's a blocking overlay (has backdrop or is fixed/fullscreen)
            var style = window.getComputedStyle(m);
            if (style.position === 'fixed' || style.position === 'absolute') {
              m.remove();
              removed = true;
            }
          });
          return removed;
        })()
        """
        _ = try? await bridge.evaluateJS(removeModalJS) as? Bool

        for _ in 0..<8 {
            let dismissModalJS = """
            (function(){
              function isVisible(el) {
                var r = el.getBoundingClientRect();
                var s = window.getComputedStyle(el);
                return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
              }
              // 0. Fast path: no visible modal-like overlay at all → nothing to do.
              var ov = document.querySelectorAll(
                '[class*="modal"], [class*="Modal"], [class*="paywall"], [class*="Paywall"], ' +
                '[class*="dialog"], [class*="Dialog"], [role="dialog"], [role="alertdialog"]'
              );
              var anyVisible = false;
              for (var v = 0; v < ov.length; v++) {
                var st = window.getComputedStyle(ov[v]);
                var rr = ov[v].getBoundingClientRect();
                if ((st.position === 'fixed' || st.position === 'absolute' || ov[v].getAttribute('role') === 'dialog' || ov[v].getAttribute('role') === 'alertdialog') &&
                    rr.width > 120 && rr.height > 60 && isVisible(ov[v])) { anyVisible = true; break; }
              }
              if (!anyVisible) return 'none';
              // 1. Close/X buttons first (language-independent).
              var closeSels = [
                '[aria-label="Close"]', '[aria-label="close"]',
                '[aria-label="Закрыть"]', '[aria-label="закрыть"]',
                '[aria-label="关闭"]', '[aria-label="關閉"]',
                '.modal-close', '.dialog-close', '.close-btn', '.close-button',
                '[class*="modal-close"]', '[class*="dialog-close"]',
                'button[class*="close"]', '[class*="btn-close"]'
              ];
              for (var s = 0; s < closeSels.length; s++) {
                var cands = document.querySelectorAll(closeSels[s]);
                for (var ci = 0; ci < cands.length; ci++) {
                  if (isVisible(cands[ci])) { cands[ci].click(); return 'close-btn'; }
                }
              }
              // 2. Dismiss buttons by text: RU / EN / ZH. Exact match first.
              var labels = [
                'понятно', 'понял', 'поняла', 'хорошо', 'ясно',
                'understood', 'got it', 'i see', 'ok', 'okay', 'dismiss', 'close',
                'закрыть', 'пропустить', 'skip', 'no thanks', 'нет, спасибо', 'не надо',
                '知道了', '明白了', '了解', '好的', '确定', '关闭', '知道了!'
              ];
              var els = document.querySelectorAll('button, [role="button"], a, div[class*="btn"], div[class*="button"], span[class*="btn"]');
              for (var i = 0; i < els.length; i++) {
                if (!isVisible(els[i])) continue;
                var t = ((els[i].innerText || els[i].textContent) || '').trim().toLowerCase();
                if (!t || t.length > 30) continue;
                for (var j = 0; j < labels.length; j++) {
                  if (t === labels[j]) { els[i].click(); return 'btn:' + t; }
                }
              }
              // 3. Substring match for short button texts (e.g. "OK, понятно!").
              for (var i2 = 0; i2 < els.length; i2++) {
                if (!isVisible(els[i2])) continue;
                var t2 = ((els[i2].innerText || els[i2].textContent) || '').trim().toLowerCase();
                if (!t2 || t2.length > 14) continue;
                for (var j2 = 0; j2 < labels.length; j2++) {
                  if (t2.indexOf(labels[j2]) !== -1) { els[i2].click(); return 'btn-sub:' + t2; }
                }
              }
              // 4. Backdrop/mask click.
              var masks = document.querySelectorAll(
                '.modal-mask, [class*="modal-mask"], [class*="backdrop"], [class*="Backdrop"], ' +
                '[class*="overlay-mask"], [class*="modal-overlay"]'
              );
              for (var k = 0; k < masks.length; k++) {
                if (isVisible(masks[k])) { masks[k].click(); return 'mask'; }
              }
              // 5. Escape as a last resort.
              document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', keyCode: 27, bubbles: true}));
              document.dispatchEvent(new KeyboardEvent('keyup', {key: 'Escape', keyCode: 27, bubbles: true}));
              return 'esc';
            })()
            """
            if let action = try? await bridge.evaluateJS(dismissModalJS) as? String,
               !action.isEmpty, action != "none" {
                MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: dismissed modal via \(action)")
                await bridge.wait(ms: 1000)
                // After clicking, re-remove any modal that re-appeared
                _ = try? await bridge.evaluateJS(removeModalJS) as? Bool
            } else {
                break
            }
        }

        // Inject CSS to prevent modals from re-appearing during model switch
        let blockModalsCSS = """
        (function(){
          var style = document.createElement('style');
          style.textContent = '[class*="modal-container"], [class*="ModalContainer"], [class*="paywall-container"], [class*="PaywallContainer"] { display: none !important; }';
          document.head.appendChild(style);
          return true;
        })()
        """
        _ = try? await bridge.evaluateJS(blockModalsCSS) as? Bool
        await bridge.wait(ms: 500)

        // Click the model selector to open the model menu.
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
        let customSel = config.customModelSelector?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelButtonSel = catalogEntry?.modelButton ?? (!(customSel ?? "").isEmpty ? customSel : nil)
        if let selectors = modelButtonSel {
            for selector in selectors.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) }) {
                if (try? await bridge.click(selector: selector)) != nil {
                    await bridge.wait(ms: 600)
                    break
                }
            }
        }

        // Look for the "Быстрый" menu item and click it.
        let fastLabels = ["Быстрый", "Fast", "快速"]
        var verifiedFastLabel: String?
        for label in fastLabels {
            let js = """
            (function(){
              var items = document.querySelectorAll('.model-item, [class*=model-item], [role="menuitem"], [role="option"], li, div');
              for (var i = 0; i < items.length; i++) {
                var t = items[i].textContent || '';
                if (t.indexOf('\(label)') !== -1 && items[i].getBoundingClientRect().width > 0) {
                  items[i].click();
                  return true;
                }
              }
              return false;
            })()
            """
            if let clicked = try? await bridge.evaluateJS(js) as? Bool, clicked {
                await bridge.wait(ms: 1500)
                // Verify the model switched.
                let verifyJS = "(function(){ var el = document.querySelector('.current-model'); return el ? el.textContent.trim() : ''; })()"
                let currentModel = (try? await bridge.evaluateJS(verifyJS) as? String) ?? ""
                MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: clicked '\(label)', current-model='\(currentModel)'")
                if currentModel.contains("Быстрый") || currentModel.contains("Fast") {
                    verifiedFastLabel = currentModel
                    break
                }
            } else {
                MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: '\(label)' item not found/clicked")
            }
        }
        guard let fastModel = verifiedFastLabel else {
            MyCoderAPIServer.appendLog("🔀 [WebChatDriver] switchToFastModel: FAILED — no Fast label verified")
            return false
        }
        // Persist the switch so the next turn does not re-inject K3 and hit
        // the same quota wall again. runWebChatTurn re-reads the persisted
        // config via effectiveSelectedModel() before every turn.
        let canonical = config.allModels.first {
            $0 == fastModel || fastModel.contains($0)
        } ?? "Быстрый"
        if config.allModels.contains(canonical) {
            var updated = config
            updated.selectedModel = canonical
            WebProviderStore.save(
                WebProviderStore.upsert(updated, in: WebProviderStore.load())
            )
        }
        return true
    }
}
