# Activity 61 — Web-provider detection and Kimi send chain audit

**Round:** 107
**Scope:** Qwen/Gwen live model discovery, per-model effort detection, myCoder Auto Free assisted detection, malformed candidate rejection, Kimi remote-chat identity binding, and background web send.
**Date:** 2026-08-15
**Status:** Source and Foundation verification complete; native WKWebView/provider runtime remains pending on macOS.

## Goal and user stories

> As a user, when I press built-in browser detection, myCoder must open the provider's real model menu, expand every bounded “more models” surface, retain all selectable model labels, detect effort only from visible effort controls, and never save headings, descriptions, or effort labels as models.

> As a user, when I press Ask myCoder Auto Free, the app must prepare the same live model menu first, provide the complete visible candidate set to the free detector, merge verified DOM candidates with AI candidates, and preserve all valid models rather than returning only the currently selected model.

> As a user, when I send through Kimi, myCoder must bind the local project/chat to a verified remote conversation identity. If the provider keeps the shell URL at `/`, the app must read the active identity from the provider DOM and persist a canonical route; it must not disable the context-mixing guard.

## Full declaration-to-consumer chain

| Chain | Declaration and source | Consumer and expected behavior | Result |
|---|---|---|---|
| Model button | `WebProviderCatalog.VendorEntry.modelDropdown` and `WebProviderConfig.customModelSelector` | `WebModelDiscovery.discoverAllModels` opens the configured live control before reading candidates. | **FIXED/source-tested** |
| Structured candidates | `BrowserAutomationBridge.readModelCandidates` | Vendor-specific selectors remain first choice; the bridge now also exposes `readVisibleModelCandidates` for model surfaces without stable classes/roles. | **FIXED/source-tested** |
| Native DOM scan | `WKWebViewBrowserBridge.readVisibleModelCandidates` | Scans visible listbox/menu/model/dropdown/popover surfaces, returns selectable leaf metadata, and never scans the entire body as models. | **FIXED/parser/source; WebKit runtime pending** |
| Nested model menu | `WebModelDiscovery.discoverAllModels` | Bounded expansion clicks include “Expand models”, “Show all models”, “View all models” and localized variants; each expanded state is fingerprinted and deduplicated. | **FIXED/source-tested** |
| Model validation | `WebModelListParser.isValidModelLabel` | Qwen/Kimi labels must have compact vendor-shaped IDs; headings, descriptions, effort labels and UI actions are rejected before persistence. | **FIXED/source-tested** |
| Effort trigger | `WebModelDiscovery.discoverEffort` | Only a visible effort/thinking selector is clicked; hidden or empty selectors are skipped and the probe can continue to the next selector. | **FIXED/source; WebKit runtime pending** |
| Effort parser | `WebModelListParser.normalizeEffortLabel` and `WebEffort.fromLabel` | Only explicit multilingual low/medium/high vocabulary maps to an effort. Unknown text returns `nil`, never implicit `.medium`. | **FIXED/source-tested** |
| Built-in detection button | `WebProviderLoginView.findModelsBuiltIn` | Runs DOM expansion, capability probes and atomic `WebModelRefreshLogic.replacing`; model and per-model effort data are persisted together. | **FIXED/source; live provider pending** |
| AI Free detection button | `WebProviderLoginView.findModelsWithAI` | Expands the live menu before reading page text, includes structured candidates and up to 60k characters of post-expansion text, then merges AI output with live candidates. | **FIXED/source; live AI/provider pending** |
| AI candidate safety | `parseAIDetectedModels` and `uniqueModelNames` | AI-only candidates remain non-selectable until verified; strict vendor normalization removes headings, descriptions and effort labels. | **PRESERVED/fixed validation** |
| Local/remote identity | `WebRemoteChatIdentityLogic` | Validates chat IDs and creates a canonical `/chat/{id}` or `/c/{id}` route from a provider shell URL. Placeholder IDs and full URLs are rejected. | **FIXED/source-tested** |
| URL chat identity | `WebChatDriver.getCurrentChatID` | Parses `/chat/` and `/c/` route IDs first. | **PRESERVED/source-tested** |
| DOM chat identity | `WebChatDriver.getCurrentChatID` plus WKWebView JavaScript | When URL has no route ID, reads `data-chat-id`, `data-conversation-id`, conversation test IDs, active-page attributes and history hrefs. | **FIXED/source-tested; WebKit runtime pending** |
| New Kimi session | `WebChatDriver.startNewSession` | Requires the active remote ID to change or the URL to change after an exact New Chat click; a stale page/history click is rejected. | **PRESERVED/source-tested** |
| Mapping persistence | `ChatPanelView.bindWebRemoteChat` and `WebRemoteChatStore` | Persists the verified remote UUID with a canonical provider route, scoped by provider/session/project/local chat. | **FIXED/source; native runtime pending** |
| Send guard | `ChatPanelView` → `WebChatDriver.runTurn` | Existing host/UUID verification and model/effort injection guards remain fail-closed; no context-mixing bypass was added. | **PRESERVED/source-tested** |

## TDD evidence

The persistent `.acceptance/test_web_regressions_round107.py` was written before production changes and failed on the missing broad candidate scanner, missing AI menu preparation, permissive effort fallback, and missing Kimi DOM identity helper. A new Swift regression suite was also added before the implementation: arbitrary model/page text initially became `.medium`, and a URL-less Kimi shell initially returned no chat identity. Both red cases became green after the chain-safe fixes.

The existing discovery fakes were kept intact and re-run. This preserved the previous contracts for vendor selectors, nested expansion, noise rejection, exact model selection and the agentic driver loop instead of replacing them with only new source markers.

## Verification gates

| Gate | Result |
|---|---:|
| Round 107 persistent source regression before implementation | **Failed as expected** |
| Round 107 persistent source regression after implementation | **PASS** |
| New strict-effort regression suite | **2/2 PASS** |
| Kimi URL-less DOM identity regression | **PASS** |
| Existing model discovery suite | **5/5 PASS** |
| Existing parser suite | **4/4 PASS** |
| Existing WebChatDriver suite | **13/13 PASS** |
| Full Foundation harness | **PASS — 363/363 with one worker** |
| Round 102/103/104/105/106 acceptance | **PASS** |
| Registry integrity | **PASS — 274 unique rows; statuses unchanged** |
| Adversarial source checks | **PASS — 12/12** |
| Swift parser on affected macOS sources | **PASS** |
| `git diff --check` | **Pending final commit gate** |
| Native macOS/WebKit provider runtime | **UNVERIFIED** |

## Devil’s-advocate review

The Qwen screenshot was not evidence of a single bad label. It exposed a layered failure: the vendor-specific selector saw only the currently rendered portion of a multi-surface menu, the expansion vocabulary did not include the exact visible action, and broad fallback parsing could confuse descriptions or effort controls with models. The fix therefore expands the live menu first, adds a bounded visible-surface scan, and validates names by vendor-shaped model syntax.

The AI Free screenshot was caused by reading `document.body.innerText` before opening or expanding the model menu. A free model could only extract the selected model because the other entries were not visible to the extractor. The AI path now receives the structured live candidates and the page text captured after menu preparation; it is still not allowed to invent selectable models.

The Kimi error was a deliberate fail-closed guard, not a reason to remove UUID verification. The old code recognized only route IDs in the URL, while Kimi may expose the active conversation through DOM attributes or history links while keeping the shell at `/`. The fix adds a pure validated DOM fallback and persists a canonical route. If the real provider exposes neither a verifiable route nor a DOM identity, the send remains blocked rather than risking context mixing.

## Separate quality ratings

**Implementation quality: 100/100 at the available source/Foundation scope.** The three reported failure chains were separated, red-tested, fixed with minimal chain-safe changes, and rechecked through 363 Foundation tests plus parser/source gates. Existing fail-closed model/effort and remote-host guards were preserved.

**Task-following quality: 100/100 for the verifiable scope.** The screenshot symptoms were traced from button/action through browser bridge, parser, persistence and final send consumer; canonical documentation and the feature registry were updated; no native runtime behavior was claimed as verified.

**Native runtime confidence: 70/100 pending macOS.** The exact Qwen/Kimi DOM attributes, menu class names, expansion timing, WebKit JavaScript return values and real provider session routes still require the user's native build and live logged-in sessions. A successful Linux harness cannot prove those WebKit/provider facts.

## Native acceptance procedure

From the repository root on macOS:

```bash
git pull origin main
./build-app.sh
```

For Qwen, press **Built-in browser detection** and confirm the result includes the models visible under **Expand more models**, not only the selected model. Then press the effort refresh action and verify that each model shows effort only when its own visible control exists; model descriptions and labels such as Auto/Fast/Deep thinking must not appear in the model catalog.

For myCoder Auto Free, first open the model menu and its expansion surfaces, then press **Ask myCoder Auto Free**. The result must preserve all valid model names returned by the live DOM/AI merge and leave AI-only rows non-selectable until verified.

For Kimi, create or select a local chat, send a short message, and inspect the browser action journal. The mapping must contain a verified remote ID and a canonical provider chat URL. Repeat in a second local project/chat and verify that the two mappings remain separate. If Kimi still reports missing identity, capture the current page URL and the DOM attributes/history route visible in the embedded browser; do not disable the context-mixing guard.
