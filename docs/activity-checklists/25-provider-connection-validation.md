# Activity 25 — Provider Connection Validation

## Audit objective

This round audits **PROV-08 Connection Validation** from custom-provider settings and form fields through `ProviderEndpointLogic`, `MyCoderApp.testProvider`, `loadModelsFromCustomProvider`, Keychain-backed API keys, model discovery, provider readiness, the model selector, and the final send route.

The confirmed defect was that `testProvider` treated any HTTP 200 response from `/models` as a successful connection. An HTML login page, malformed JSON, or a valid JSON object with an empty model list could therefore be reported as connected even though the provider could not supply a model. The actual model loader had stronger checks, but the standalone validation action was inconsistent and could mislead the user.

## Button, field, and function checklist

| # | UI control/action | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Provider type selector | `ModelSettingsView` form → `ProviderType` | Select a supported provider type and apply the correct endpoint/API-key defaults. | **Pass by existing endpoint/default tests; native UI UNVERIFIED.** |
| 2 | Base URL field | form binding → `ProviderEndpointLogic.normalizedBaseURL` | Accept only HTTP(S) URLs with a host, no query/fragment, and normalized trailing slash. | **Pass:** invalid schemes/hosts/query/fragment are rejected by existing tests. |
| 3 | API key field | form → Keychain persistence → request Authorization | Store secrets securely and send Bearer auth when provided; do not require a key for Ollama/ACP/OpenCode Zen defaults. | **Pass by source/tests; Keychain/network runtime UNVERIFIED.** |
| 4 | Test Connection action | settings form → `AppState.testProvider` → `/models` | Use normalized `/models`, timeout, optional Bearer header, HTTP response, and body validation. | **Fixed:** success now requires a 2xx response plus at least one real model identifier. |
| 5 | HTTP failure | URLSession → status code | Reject 401/403/404/5xx even if body contains model-shaped data. | **Fixed and tested.** |
| 6 | HTML/login response | status 200 + non-JSON body | Reject rather than report a false connection. | **Fixed and tested.** |
| 7 | Malformed JSON response | status 200 + invalid JSON | Reject with a failed validation result; no false connected state. | **Fixed and tested.** |
| 8 | Empty model list | status 200 + `{data:[]}` or `{models:[]}` | Reject because no model can be selected or sent. | **Fixed and tested.** |
| 9 | OpenAI-compatible response | `{data:[{id:...}]}` | Accept non-empty trimmed IDs. | **Pass and tested.** |
| 10 | Ollama/Google-style response | `{models:[{name/id:...}]}` | Accept non-empty names/IDs after removing `models/` prefix. | **Pass by validation contract; live vendor schema UNVERIFIED.** |
| 11 | Invalid model identifier | model object with missing/blank ID/name | Ignore blank entries and reject if all entries are invalid. | **Pass by pure validation contract.** |
| 12 | Model loader after save | `updateCustomProvider`/`saveCustomProvider` → `loadModelsFromCustomProvider` | Parse valid model lists, persist models, and reconcile selected provider/model. | **Pass by source; live network runtime UNVERIFIED.** |
| 13 | Empty loader result | loader → `providerModelLoadMessages` | Show a useful “no models found” message and avoid overwriting valid prior models with empty state. | **Pass by source.** |
| 14 | HTTP loader error | loader → status/body → message | Surface status and bounded response context without claiming readiness. | **Pass by source.** |
| 15 | Refresh Models action | settings refresh → loader | Re-query the provider and update models only after a valid non-empty result. | **Pass by source; native action UNVERIFIED.** |
| 16 | Provider enable/disable | row toggle → persistence → `providerOptions` | Disabled provider is not offered as ready; enabling triggers model loading. | **Pass by source; native UI UNVERIFIED.** |
| 17 | Remove provider | delete action → Keychain delete → config delete → selection reconciliation | Remove credentials/config and clear invalid active selection. | **Pass by source; Keychain/native UI UNVERIFIED.** |
| 18 | Model selector after validation | provider option → models → selected model | Do not expose a connected custom provider with no usable models. | **Pass through existing provider-option/readiness contracts.** |
| 19 | Send readiness | selected custom provider → `SendProviderReadinessLogic` → `SendReadinessLogic` | Block sends when disabled, disconnected, or model-empty and provide a reason. | **Pass by existing readiness tests.** |
| 20 | Direct programmatic test | `testProvider` called outside the form | Return false for any invalid response without mutating provider state. | **Fixed by pure payload contract; native network execution UNVERIFIED.** |

## Confirmed defect and TDD evidence

### HTTP 200 alone was treated as a successful connection

`MyCoderApp.testProvider` previously returned `true` whenever `/models` returned HTTP 200. It did not inspect the response body. This differed from `loadModelsFromCustomProvider`, which already required valid JSON and a non-empty parsed model list. A provider could therefore pass “Test Connection” while returning an HTML login page or no models at all.

`ProviderConnectionValidationLogicTests` was written first. The red run failed because the payload-aware validation contract did not exist. The green `ProviderConnectionValidationLogic.isValidModelsResponse` requires a 2xx status and at least one non-empty model ID/name from OpenAI-style `data` or named `models` payloads. `MyCoderApp.testProvider` now delegates to that contract and fails closed for malformed, empty, or non-success responses.

## Remaining limitations

PROV-08 remains **PARTIAL**. Linux cannot execute URLSession against real provider endpoints, Keychain behavior, SwiftUI settings controls, TLS/proxy/captive-login behavior, or provider-specific response variants. The pure validation contract prevents false positives at the response boundary; live network reachability and user-visible localized error presentation require macOS/runtime verification.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red payload-aware validation regressions | **failed as expected** | Missing validation contract |
| Green provider-validation regressions | **4/4 passed** | Valid payload, invalid body, empty list, non-success status |
| Full Foundation harness | **240/240 passed** | Existing contracts plus PROV-08 regressions |
| Swift parser validation | **passed** | Validation helper and MyCoderApp wiring |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Real network/Keychain execution | **UNVERIFIED** | Requires macOS runtime and provider endpoints |
| SwiftUI settings interaction | **UNVERIFIED** | Requires native UI runtime |

The **implementation quality score is 94/100**. Connection validation now checks the actual model payload and fails closed, while live network, Keychain, provider variants, and localized UI behavior remain.

The **task-following score is 100/100**. Every PROV-08 field/action/function was traced, the confirmed false-positive defect received red tests before the fix, and network/runtime boundaries are explicitly UNVERIFIED.

> A successful HTTP status is evidence that an endpoint responded, not evidence that the provider is usable; connection validation must verify the model payload required by the next user action.
