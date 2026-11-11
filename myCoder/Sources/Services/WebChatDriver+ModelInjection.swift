import Foundation

extension WebChatDriver {
    /// Inject the currently selected model and effort into the web UI before
    /// sending a message. Reads the vendor selectors from the catalog; if the
    /// dropdowns are present, clicks them and selects the matching option.
    /// Returns false when a requested model/effort could not be confirmed. The
    /// caller must abort before typing so a recovery retry cannot duplicate text.
    func injectModelAndEffort(emit: (WebChatEvent) -> Void) async -> Bool {
        // Round 30b: let post-submission navigation settle first.
        await waitForPageURLStability()
        // Resolve vendor-specific selectors from the catalog. A custom provider
        // may have no bundled entry, but can still be safe when the user saved a
        // custom model selector. A selected model without either route is a hard
        // failure: never send under an unverified model.
        let catalogEntry = try? WebProviderCatalog.loadBundled().selectors(for: config.vendor.id)
        var injectionSucceeded = true

        // Model selection requires exact confirmation before sending.
        if !config.selectedModel.isEmpty {
            let configuredModelButton = config.customModelSelector?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? catalogEntry?.modelButton
            let modelSelectors = (configuredModelButton?.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? [])
                .filter { !$0.isEmpty }
            guard !modelSelectors.isEmpty else {
                injectionSucceeded = false
                emit(.modelInjectionFailed(
                    "No model selector is configured; injection was blocked before send."
                ))
                return false
            }
            // Audit 2026-09-06 (Claude): the model button's own label carries
            // the CURRENT model (e.g. "Sonnet 5 Max" = model Sonnet 5 + Effort
            // Max). When the target model is already active, opening the menu
            // is unnecessary AND the menu may not list the current model in
            // its current state (live evidence: the menu showed only gated
            // families while Sonnet 5 was already selected), which used to
            // fail the send with a false "Model not found".
            // Audit 2026-09-08 (Kimi): the model button packs "Name + effort"
            // ("K3 Swarm / Высокий"), so a substring check treats "K3 Swarm"
            // as "K3" and sends under the wrong model. Kimi exposes the bare
            // model name in `.model-name .name` — compare it EXACTLY. Also, a
            // menu click may navigate to another product surface (live: "K3"
            // landed on /agent*); return to the chat surface and re-verify.
            let activeLabelSelector: String? = {
                switch config.vendor {
                case .kimi: return ".current-model .model-name .name"
                default: return nil
                }
            }()
            let activeIsTarget: Bool = await {
                if let labelSelector = activeLabelSelector,
                   let label = try? await bridge.readText(selector: labelSelector),
                   !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return label.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .lowercased() == config.selectedModel.lowercased()
                }
                if let activeText = (try? await bridge.readText(selector: modelSelectors[0])) {
                    return activeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        .contains(config.selectedModel)
                }
                return false
            }()
            if activeIsTarget {
                await bridge.wait(ms: 200)
            } else {
            var openedSelector: String?
            for selector in modelSelectors {
                guard (try? await bridge.exists(selector: selector)) == true else { continue }
                do {
                    try await bridge.click(selector: selector)
                    openedSelector = selector
                    break
                } catch {
                    continue
                }
            }

            // Audit 2026-09-08 (ChatGPT 2026 UI): free accounts have NO model
            // switcher at all — one automatic model plus the Reasoning pill.
            // Discovery proves this by emitting synthetic "ChatGPT Auto…"
            // labels. When the control is absent from the page AND the
            // selected model is such an auto label, there is nothing to
            // inject; requiring a menu click would block every send on a
            // page that has nothing to click (live: all ChatGPT sends died
            // with "model control is unavailable" although the message had
            // already been submitted and answered). Effort injection below
            // still runs.
            let autoModelBypass = openedSelector == nil && config.vendor == .chatgpt
                && config.selectedModel.lowercased().hasPrefix("chatgpt auto")
            if autoModelBypass {
                await bridge.wait(ms: 200)
            } else if let openedSelector {
                try? await bridge.waitForSelector(selector: "div.model-item, [class*='model-item'], [role='option']", timeout: 5000)
                await bridge.wait(ms: 500)
                let modelText = config.selectedModel
                let itemSelector = catalogEntry?.modelItem ?? "[role='option'], [class*='option']"
                // Round 30b: menus can render late; re-open and re-match within
                // a small bounded budget instead of one-shot failing.
                var clicked = false
                for attempt in 1...SendSubmissionPolicy.maxMatchRetries {
                    if attempt > 1 {
                        try? await bridge.click(selector: openedSelector)
                        await bridge.wait(ms: SendSubmissionPolicy.matchRetryDelayMs)
                        try? await bridge.waitForSelector(selector: "div.model-item, [class*='model-item'], [role='option']", timeout: 5000)
                        await bridge.wait(ms: SendSubmissionPolicy.matchRetryDelayMs)
                    }
                    clicked = (try? await bridge.clickVisibleTextExact(selector: itemSelector, text: modelText)) == true
                    if clicked { break }
                }
                if clicked {
                    // Let the model menu close and the provider commit its state
                    // before touching the independent effort control.
                    await bridge.wait(ms: 800)
                    // Audit 2026-09-08/09 (Kimi): a menu click may navigate to a
                    // different product surface. For agent models (K3/K3 Swarm)
                    // /agent IS the right surface — the choice is verified
                    // there (live: label reads "K3"). Only navigate back when
                    // the surface does NOT match the selected model; a choice
                    // that did not stick is an honest failure, not a silent
                    // send under the wrong model.
                    let afterURL = (try? await bridge.currentURL()) ?? ""
                    if WebChatSurfaceLogic.isProductDetour(afterURL: afterURL,
                                                           chatURL: config.chatURL,
                                                           vendor: config.vendor,
                                                           selectedModel: config.selectedModel) {
                        try? await bridge.navigate(to: WebChatSurfaceLogic.targetSurfaceURL(
                            chatURL: config.chatURL,
                            vendor: config.vendor,
                            selectedModel: config.selectedModel
                        ))
                        try? await bridge.waitForSelector(selector: selectors.input, timeout: 10_000)
                        await bridge.wait(ms: 800)
                        let committed: Bool = await {
                            if let labelSelector = activeLabelSelector,
                               let label = try? await bridge.readText(selector: labelSelector),
                               !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                return label.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                                    .lowercased() == config.selectedModel.lowercased()
                            }
                            return false
                        }()
                        if !committed {
                            injectionSucceeded = false
                            emit(.modelInjectionFailed(
                                "Model '\(modelText)' did not stay selected after returning to the chat page; injection was blocked before send."
                            ))
                        }
                    }
                } else {
                    // Toggle the same control once to avoid leaving a menu overlay
                    // in front of the composer. A visible dropdown without an exact
                    // confirmed option is still a hard failure: never send under a
                    // different model than the one shown in the composer.
                    try? await bridge.click(selector: openedSelector)
                    injectionSucceeded = false
                    emit(.modelInjectionFailed(
                        "Model '\(modelText)' was not found; injection was blocked before send."
                    ))
                }
            } else {
                injectionSucceeded = false
                emit(.modelInjectionFailed(
                    "The page model control is unavailable; model injection was blocked before send."
                ))
            }
            }
        }

        // Effort is optional: models without a live effort selector are not
        // injected. If a requested effort selector exists but cannot confirm the
        // choice, block before typing so recovery cannot duplicate a turn.
        let selectedModel = config.discoveredModels.first(where: { $0.name == config.selectedModel })
        let effortToInject: WebEffort? = {
            // Before any live model profile exists, preserve the legacy
            // persisted-effort path for vendors whose catalog exposes a
            // universal control. Once profiles exist, an undetected model has
            // no verified capability and must not inherit another model's
            // effort setting.
            guard !config.discoveredModels.isEmpty else { return config.effort }
            guard let selectedModel else { return nil }
            return selectedModel.availableEfforts.contains(config.effort) ? config.effort : nil
        }()
        if let candidates = effortToInject.flatMap({ effortCandidates(for: $0) }), !candidates.isEmpty,
           let catalogEntry {
            let selectors = (catalogEntry.effortDropdown?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } ?? [])
                .filter { !$0.isEmpty }
            var anySuccess = false
            var foundControl = false
            var lastError = ""
            for selector in selectors {
                do {
                    guard (try? await bridge.exists(selector: selector)) == true else { continue }
                    foundControl = true
                    try await bridge.click(selector: selector)
                    try? await bridge.waitForSelector(selector: "[class*='effort'], [class*='thinking'], [role='option'], [class*='option']", timeout: 5000)
                    await bridge.wait(ms: 500)
                    let itemSelector = catalogEntry.effortItem ?? "[role='option'], [class*='option']"
                    // Round 30b: match ANY known label variant, retrying with a
                    // re-opened menu within the bounded budget.
                    for attempt in 1...SendSubmissionPolicy.maxMatchRetries {
                        if attempt > 1 {
                            try? await bridge.click(selector: selector)
                            await bridge.wait(ms: SendSubmissionPolicy.matchRetryDelayMs)
                        }
                        var labelClicked = false
                        for candidate in candidates where !labelClicked {
                            labelClicked = (try? await bridge.clickVisibleTextExact(selector: itemSelector, text: candidate)) == true
                        }
                        if labelClicked {
                            // Keep effort injection isolated from the model menu.
                            await bridge.wait(ms: 800)
                            anySuccess = true
                            break
                        }
                    }
                    if anySuccess { break }
                    lastError = "effort option not found"
                } catch {
                    lastError = error.localizedDescription
                }
            }
            if foundControl && !anySuccess {
                injectionSucceeded = false
                emit(.effortInjectionFailed(
                    L.t(AppLocalizationKey.locWebEffortNote)
                        .replacingOccurrences(of: "{0}", with: lastError.isEmpty ? "effort option not found; effort injection was blocked before send" : lastError)
                ))
            }
        }

        // Parameters are optional vendor controls. Apply only the user's saved
        // overrides and only when discovery identified matching live controls;
        // absence never blocks a normal send.
        if let model = config.discoveredModels.first(where: { $0.name == config.selectedModel }) {
            await injectParameters(ModelCallParametersStore.parameters(for: config.selectedModel),
                                   profile: model.parameterProfile)
        }
        return injectionSucceeded
    }

    func injectParameters(_ parameters: ModelCallParameters,
                                  profile: WebModelParameterProfile) async {
        guard parameters.isCustomized, !profile.availableKeys.isEmpty else { return }
        let fragment = ModelCallParametersStore.requestFragment(parameters)
        guard let data = try? JSONSerialization.data(withJSONObject: fragment),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = """
        (function(){
          const values = \(json);
          const visible = el => {
            const s = getComputedStyle(el), r = el.getBoundingClientRect();
            return s.display !== 'none' && s.visibility !== 'hidden' && r.width > 0 && r.height > 0;
          };
          const nodes = Array.from(document.querySelectorAll('input, textarea, select, [role=spinbutton], [role=slider]')).filter(visible);
          const aliases = {
            temperature: /temperature|temp/i,
            max_tokens: /max.?tokens?|max.?output|token.?limit/i,
            top_p: /top.?p/i,
            system: /system.?prompt/i
          };
          let applied = 0;
          Object.keys(values).forEach(key => {
            if (!aliases[key]) return;
            const el = nodes.find(node => {
              const label = ((node.getAttribute('name') || '') + ' ' + (node.getAttribute('aria-label') || '') + ' ' + (node.id || '') + ' ' + (node.innerText || '')).toLowerCase();
              return aliases[key].test(label);
            });
            if (!el) return;
            const value = String(values[key]);
            if (el.tagName.toLowerCase() === 'textarea' || el.tagName.toLowerCase() === 'input') {
              const proto = el.tagName.toLowerCase() === 'textarea' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
              const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
              if (descriptor && descriptor.set) descriptor.set.call(el, value); else el.value = value;
            } else {
              el.setAttribute('data-mycoder-value', value);
            }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            applied += 1;
          });
          return applied;
        })();
        """
        _ = try? await bridge.evaluateJS(script)
    }
}
