# Activity 47 — Input and Provider Readiness

## Audit objective

This round audits **INP-10**, **INP-14**, and **PROV-08** from the user’s send button, Enter key, parameter editor, and Test Connection/Refresh Models actions through validation, route selection, request-body construction, persistence, and visible recovery feedback. The audit treats whitespace, empty payloads, malformed alternate schemas, duplicate model rows, and disconnected/unknown routes as first-class adversarial cases.

## Full chain checklist

| Story | Chain audited | Expected behavior | Result |
|---|---|---|---|
| INP-10 | Enter/button → shared send gate → provider/model/connection readiness → send callback or actionable reason | Send is enabled only for nonempty text/attachments, valid model/provider, ready route, and idle state; loading displays stop and Enter cannot start a second send. | **Fixed Round 93 whitespace-provider gate; 317/317 Foundation tests; native SwiftUI/AppKit keyboard/cancellation runtime UNVERIFIED.** |
| INP-14 | Model parameter popover/settings editor → validation → per-model UserDefaults → request fragment → Direct/Serve/ACP/Auto Free paths | Numeric parameters are range-checked; system prompt is trimmed; blank values mean provider defaults; parameters are applied per model and do not leak across models. | **Fixed Round 93 shared/inline system-prompt normalization; 12/12 focused parameter tests; native popover/live provider application UNVERIFIED.** |
| PROV-08 | Test Connection and Refresh Models → HTTP status/JSON → canonical model extraction → model catalog/UI readiness | Only successful nonempty model payloads count as connected; blank/duplicate IDs are rejected or normalized; alternate `name` is used when `id` is blank; stale/invalid refresh cannot populate junk model choices. | **Fixed Round 93 canonical parser and refresh wiring; 6/6 validator tests; URLSession/settings runtime UNVERIFIED.** |

## Detailed manual trace

| # | Action/function | Chain and invariant | Result |
|---:|---|---|---|
| 1 | Send button idle state | `MessageInputToolbar` passes `canSend` and `isLoading` into `SendStopButton`; idle shows arrow and disables the action when readiness is false. | **Pass by source.** |
| 2 | Stop button loading state | `SendStopButton` switches to stop action while loading; it does not invoke `onSend`. | **Pass by source; native cancellation UNVERIFIED.** |
| 3 | Centered Enter | `CenteredInputCard.inputCore` calls `SendButtonActivationLogic.canInvokeSend` before `onSend`, matching the visual button gate and recording an attempted send for empty-input feedback. | **Pass by source/tests.** |
| 4 | Bottom-bar Enter | `BottomInputBar` uses the same activation helper; loading and invalid readiness are blocked. | **Pass by source.** |
| 5 | Empty input | Text is trimmed and attachments are considered; blank text without an image/file is blocked and the centered card reveals an actionable reason after attempted send. | **Pass by source/tests.** |
| 6 | Provider/model readiness | Model validation prefers a nonblank effective model; provider validation now trims the provider ID and rejects empty/whitespace selections even when Serve is connected. | **Fixed Round 93.** |
| 7 | Direct/web/custom route | Route-specific readiness is checked before the send callback; connected Serve cannot approve an unrelated or empty provider route. | **Pass by source/tests.** |
| 8 | Parameter popover open | `ModelSettingsView.openParameters` loads values by model ID and clears the prior validation error. | **Pass by source.** |
| 9 | Parameter reset | Reset clears all fields and immediately removes the per-model entry. | **Pass by source.** |
| 10 | Numeric parameter validation | Temperature is finite and in 0…2; top-p is finite and in 0…1; max tokens is a positive integer; blank fields remain unset. | **Pass by shared parser/tests; inline settings runtime UNVERIFIED.** |
| 11 | System prompt normalization | Shared parser and inline settings editor trim meaningful prompts and map whitespace-only values to nil. | **Fixed Round 93.** |
| 12 | Per-model persistence | Store keys are model IDs; loading one model does not reuse another model’s parameters; whitespace-only prompts no longer create customized entries. | **Fixed Round 93.** |
| 13 | Request fragment | Numeric keys are emitted only when set; system prompt is emitted as trimmed `system` only when nonblank. | **Fixed Round 93/tests.** |
| 14 | Direct route application | ChatPanel builds `ChatHistoryBuilder.messages(systemPrompt: params.systemPrompt, ...)` and passes numeric parameters to `DirectChatClient.send`; Direct body correctly omits a body-level `system` key because it is a message. | **Pass by source; live provider UNVERIFIED.** |
| 15 | Serve/ACP/Auto Free application | Serve/ACP request fragments include numeric/system keys; Auto Free prepends provider and model prompts and passes model parameters to its client. | **Pass by source/tests; live provider UNVERIFIED.** |
| 16 | Test Connection | Settings action calls `AppState.testProvider`; status must be 2xx and model payload must parse into at least one usable model ID. | **Pass by source.** |
| 17 | Refresh Models | Custom refresh now calls the same canonical extractor as Test Connection, filters blanks, falls back from blank ID to name, strips only a leading `models/`, deduplicates, sorts, and rejects an empty result. | **Fixed Round 93.** |
| 18 | Invalid/HTML/empty response | Non-2xx, invalid JSON, and empty usable model lists produce failure instead of a green connection or junk model catalog. | **Pass by tests/source.** |

## Confirmed defects and TDD evidence

### INP-10/PROV-08 — empty provider IDs passed the connected-Serve fallback

`SendProviderReadinessLogic.connectionValidationError` trimmed the selected provider ID, but its empty branch returned nil when Serve was connected. This allowed an empty or whitespace route to appear ready at the lower gate. A red Foundation test was written first. The helper now returns the generic provider error for every empty selection; `SendReadinessLogic.sendValidationError` also trims the provider ID and returns the actionable “Select a provider” message.

### INP-14 — system prompts were padded and whitespace-only values persisted

The shared parser returned the original prompt after only checking trimmed emptiness. The settings editor duplicated parsing and also stored the raw prompt. The per-model store considered whitespace customized and serialized padded prompts. Red tests were written first for parser trimming, whitespace-only store entries, and request-fragment trimming. The parser, settings editor, store load/set, customization badge, and request fragment now share normalized behavior.

### PROV-08 — Refresh Models bypassed canonical response validation

The Test Connection path checked for a successful nonempty model payload, but the custom refresh path independently extracted raw strings. It could accept whitespace IDs, ignore a valid `name` when `id` was blank, and diverge in prefix/deduplication behavior. A red canonical extraction test was written first. `ProviderConnectionValidationLogic.modelIDs` is now the shared parser used by validation and refresh.

## Evidence

| Check | Result | Boundary |
|---|---:|---|
| INP-10/PROV-08 whitespace-provider red test | **failed as expected → 1/1 passed** | Foundation readiness logic |
| INP-10 wrapper whitespace-provider regression | **written first; parser/native UI verification UNVERIFIED** | macOS `SendReadinessLogic` wrapper |
| INP-14 prompt parser red test | **failed as expected → 5/5 passed** | Foundation parser |
| INP-14 parameter-store red tests | **failed as expected → 7/7 passed** | Foundation UserDefaults/serialization |
| PROV-08 blank-id/name fallback red test | **failed as expected → 5/5 passed** | Foundation validator |
| PROV-08 canonical extraction red compile test | **failed as expected → 6/6 passed** | Foundation validator/parser |
| Full Foundation harness | **317/317 passed** | Linux-safe suites |
| Adversarial source checks | **12/12 passed** | Existing web/model safety invariants |
| Swift parser validation | **passed** | Changed production and test Swift |
| `git diff --check` | **passed** | No trailing whitespace |

## Status and scores

The confirmed input/provider defects are fixed. The stories remain **PARTIAL** wherever confirmation depends on SwiftUI/AppKit keyboard behavior, native cancellation, URLSession, Keychain, settings popovers, or live provider responses. No Linux result is represented as a native runtime PASS.

| Story | Code quality | Task adherence | Target-runtime confidence |
|---|---:|---:|---:|
| INP-10 | 98/100 | 100/100 | 0/100 |
| INP-14 | 98/100 | 100/100 | 0/100 |
| PROV-08 | 99/100 | 100/100 | 0/100 |

> A connected server is not proof that an empty route is valid, and a successful HTTP status is not proof that a provider returned a usable model catalog. Both boundaries now fail closed and share one parser.
