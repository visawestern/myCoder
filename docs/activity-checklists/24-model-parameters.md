# Activity 24 — Model Parameters Dialog

## Audit objective

This round audits **INP-14 Model Parameters Dialog** from `MessageInputToolbar` and `ModelSelectionPresentationLogic` into `ModelParametersButton`, `ModelCallParametersStore`, `ModelCallParameters`, request-fragment serialization, direct OpenAI-compatible sends, Serve/ACP payloads, web parameter injection, and model-specific persistence.

The dialog already opened for a selected effective model and persisted values per model ID. The confirmed defect was that its text fields accepted arbitrary numeric strings, including temperature outside `0–2`, Top P outside `0–1`, zero/negative max tokens, non-integer tokens, and non-finite values. `save()` converted invalid text to nil and silently persisted a partial/default parameter set, making the user believe unsafe input had been saved. Round 70 adds red-first validation tests and an inline error that keeps the popover open until the values are corrected or reset.

## Button, field, and function checklist

| # | UI control/action | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Parameters gear visibility | `MessageInputToolbar` → `ModelSelectionPresentationLogic.shouldShowParameters` | Show the gear whenever a valid selected/effective model exists, including web/Auto Free effective models. | **Pass by source/tests; native UI UNVERIFIED.** |
| 2 | Gear click | `ModelParametersButton` → `load()` → popover | Load the current model’s persisted values and open the editor. | **Pass:** load resolves parameter model ID from effective model; native popover UNVERIFIED. |
| 3 | Model identity title | `displayModel(selectedModel:effectiveModel:)` | Show the actual effective model being edited, not an empty web-provider AppState model. | **Pass by source.** |
| 4 | Temperature field | text field → validation → `ModelCallParameters.temperature` | Accept blank/provider default or a finite value from `0` through `2`; reject other values. | **Fixed and tested.** |
| 5 | Max tokens field | text field → validation → `maxTokens` | Accept blank/provider default or a positive integer; reject zero, negative, decimal, overflow, and non-numeric values. | **Fixed and tested.** |
| 6 | Top P field | text field → validation → `topP` | Accept blank/provider default or a finite value from `0` through `1`; reject other values. | **Fixed and tested.** |
| 7 | System prompt editor | `TextEditor` → validation → optional `systemPrompt` | Preserve meaningful prompt text; blank/whitespace means unset/provider default. | **Pass by source/tests; native editor UNVERIFIED.** |
| 8 | Save valid values | Save button → `parse` → `ModelCallParametersStore.set` → popover dismiss | Persist all valid values under the effective model ID and close only after success. | **Fixed:** validation is required before persistence; native click/persistence UNVERIFIED. |
| 9 | Save invalid values | Save button → parse failure → inline error | Keep the popover open, preserve input for correction, and do not overwrite existing saved values. | **Fixed by source:** validation message and early return exist. |
| 10 | Reset button | `resetAll()` → clear fields → store removes model key | Restore provider defaults and remove custom values for only the active model. | **Pass by source/tests; native interaction UNVERIFIED.** |
| 11 | Switch model then reopen | effective model changes → gear load | Load a separate parameter record for the new model; never leak values across model IDs. | **Pass by store contract.** |
| 12 | Direct OpenAI-compatible route | `ModelCallParametersStore.parameters` → `DirectChatClient.send` → request fragment | Forward only set validated keys, using `max_tokens` wire name and optional system key. | **Pass by E06/direct tests.** |
| 13 | Serve route | `MessageSendOptions`/request body → request fragment | Forward validated overrides without injecting nil/default keys. | **Pass by existing E06 tests.** |
| 14 | ACP route | `ACPMessageTypes` → request fragment | Forward supported overrides consistently with direct/Serve routes. | **Pass by source/tests; live ACP runtime UNVERIFIED.** |
| 15 | Web route | `WebChatDriver.injectParameters` → browser controls | Apply only customized values whose live parameter profile exposes matching controls. | **Pass/partial:** safe optional injection exists; live vendor controls UNVERIFIED. |
| 16 | Empty model state | no selected/effective model → gear absent/guarded | Do not persist parameters under an empty key or show a misleading editor. | **Pass by source.** |
| 17 | Non-finite numeric input | `Double("nan")`/infinite-like text → validation | Reject non-finite values rather than persisting them or serializing invalid JSON. | **Fixed:** parse requires finite doubles. |
| 18 | Error message recovery | invalid save → edit/reset → save | Error clears after a valid save or reset; user can recover without closing/reopening. | **Fixed by source.** |

## Confirmed defect and TDD evidence

### Unsafe numeric values were silently discarded/persisted as defaults

`ModelParametersButton.save()` previously built `ModelCallParameters` directly from `Double(...)`/`Int(...)`. Invalid or out-of-range text became nil without feedback, and out-of-range valid numbers were accepted. The store then treated the result as a legitimate parameter set or removed the model entry, depending on which fields parsed. This made the dialog’s apparent state diverge from the persisted state.

`ModelCallParametersValidationLogicTests` was written first. The red run failed because the validation contract did not exist. The green parser allows blanks as provider defaults, enforces temperature `0–2`, Top P `0–1`, positive integer max tokens, finite doubles, and meaningful system prompts. `ModelParametersButton.save()` now rejects invalid input, shows an inline error, retains the popover, and writes only validated values.

## Remaining limitations

INP-14 remains **PARTIAL**. Linux cannot execute SwiftUI popovers, native text editors, accessibility, or live provider parameter controls. The direct/Serve/ACP request-fragment consumers are covered by existing Foundation tests. Web parameter injection remains dependent on vendor DOM controls and is explicitly unverified at runtime.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red parameter-validation regressions | **failed as expected** | Missing parser/bounds contract |
| Green parameter-validation regressions | **4/4 passed** | Valid, blank, float ranges, positive integer |
| Full Foundation harness | **236/236 passed** | Existing contracts plus INP-14 validation tests |
| Swift parser validation | **passed** | Validation helper, model store, parameter popover |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/AppKit popover | **UNVERIFIED** | Requires macOS runtime |
| Live web parameter controls | **UNVERIFIED** | Requires authenticated vendor pages |

The **implementation quality score is 94/100**. Unsafe silent parameter handling is fixed with a small pure parser and inline recovery state; localized copy, native interaction, and live vendor controls remain.

The **task-following score is 100/100**. Every parameter field/button/consumer was traced, red tests preceded the fix, and native/live behavior remains explicitly UNVERIFIED.

> A parameter editor must never turn invalid user input into an apparently successful default; it should preserve the attempted value and explain how to correct it.
