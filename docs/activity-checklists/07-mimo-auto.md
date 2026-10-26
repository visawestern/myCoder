# Activity 07 — myCoder Auto Free

> Historical identifiers such as `mimo-auto` remain only for preference migration and `mimoServe` remains the separate local-server transport. The user-facing built-in provider is **myCoder Auto Free** with OpenCode Zen as its anonymous route.

Источники: `MyCoderAutoFreeProvider.swift`, `MyCoderAutoFreeClient.swift`, `MyCoderAutoFreeHistoryLogic.swift`, `MyCoderAutoFreeFailoverLogic.swift`, `MyCoderAutoFreeContentLogic.swift`, `SendRouteResolver.swift`, `SendReadinessLogic.swift`, `MyCoderApp.swift`, `ChatPanelView.swift`, `ProvidersSettingsView.swift`, `NotificationService.swift`.

## Full action inventory and chain audit

| # | Действие | Trigger → handler → state/persistence → consumer | Ожидаемое поведение | Code quality | Task fit | Runtime status |
|---:|---|---|---|---:|---:|---|
| 1 | Built-in provider option | `AppState.providerOptions` → `MyCoderAutoFreeStore.provider` → `ProviderOption` → provider picker | myCoder Auto Free always appears, is built-in and cannot be deleted; it does not require MiMo Serve | 95/100 | 100/100 | CODE VERIFIED; macOS picker UNVERIFIED |
| 2 | Fresh default selection | store catalog refresh → `provider.isReady` → `validateAndReconcileSelections` → `selectProvider` | A clean install selects myCoder Auto Free only after at least one live eligible free model is known; no synthetic model is presented as ready | 94/100 | 100/100 | CODE/HARNESS; startup/network UNVERIFIED |
| 3 | Legacy preference migration | defaults `mimo-auto` → `migrateLegacyPreferences` → `mycoder-auto-free` → selection restore | Existing explicit legacy choices survive the rename without showing obsolete branding | 96/100 | 100/100 | CODE; macOS preference migration UNVERIFIED |
| 4 | Anonymous catalog refresh | Settings Refresh catalog → `store.refreshModels` → `GET /zen/v1/models` → allow-listed eligible models → published store state | Refresh uses no API key, excludes paid IDs, preserves last known catalog on transient failure, and reports status/timestamp | 93/100 | 100/100 | CODE; live OpenCode/network UNVERIFIED |
| 5 | Model list and model switch | compact selected row/menu → `selectModel` → selected ID/status/persistence → `effectiveSelectedModel` and store send loop | Current model is shown compactly; all live free models are switchable; selection persists and resets failure count | 95/100 | 100/100 | CODE; visual/live catalog UNVERIFIED |
| 6 | Lock/unlock model | lock icon or Lock selected model toggle → `setModelLocked` → persisted lock flag → `streamChat` failure policy | Locked model never fails over automatically; unlocked model may fail over; lock is available only for a live selected model | 94/100 | 100/100 | CODE; live failure UX UNVERIFIED |
| 7 | System prompt | TextEditor → Save prompt → `setSystemPrompt` → persisted prompt → `streamChat` prepends it before every attempt | Saved system prompt is explicit, persistent and applied to every free-model request, including retry/failover attempts | 94/100 | 100/100 | CODE; live prompt capture UNVERIFIED |
| 8 | Model parameters | Model Parameters UI → `ModelCallParametersStore` → `streamChat` request body | Saved temperature/max tokens/top-p/system prompt overrides are validated and included in the anonymous OpenAI-compatible request | 92/100 | 100/100 | CODE; live request capture UNVERIFIED |
| 9 | Provider readiness/send gating | `SendReadinessLogic` → `autoFreeReady` and model/provider validation → composer send state | Send is disabled with an actionable reason while the catalog is unavailable; after refresh, a valid model can send without MiMo Serve | 94/100 | 100/100 | CODE/HARNESS; macOS/network UNVERIFIED |
| 10 | Ordinary send route | composer send → `SendRouteResolver.route` → `.autoFree` → `ChatPanelView` Auto Free branch → `store.streamChat` | Message never falls into Serve; direct anonymous OpenCode SSE receives the selected model and attachments | 94/100 | 100/100 | CODE; live network UNVERIFIED |
| 11 | Conversation history | Auto Free branch → `messageStore` prior turns → `MyCoderAutoFreeHistoryLogic` → `Message` array → client request | Every new turn includes the last finished user/assistant turns; empty/in-flight placeholders and stale system rows are excluded; current attachments remain on the new user message | 96/100 | 100/100 | FOUNDATION/HARNESS; live request context UNVERIFIED |
| 12 | Attachments | composer files/images → `autoFreeMessageParts` → text/image/file parts → `MyCoderAutoFreeClient.Message.Content` encoder | Images use image URLs, readable files use bounded text parts, unsupported files produce visible notices rather than silent loss | 93/100 | 100/100 | FOUNDATION/HARNESS; macOS picker/live payload UNVERIFIED |
| 13 | Stream rendering | `chatCompletion(stream: true)` → SSE `data:` lines → content/reasoning deltas → assistant message | Non-empty deltas render while loading; empty stream becomes an explicit error, not a blank successful bubble | 94/100 | 100/100 | CODE; live SSE/WebKit not involved but network UNVERIFIED |
| 14 | Immediate failover | HTTP 429/model-unavailable/typed rate error → `shouldSwitchImmediately` → next eligible model → persisted switch + notification | Rate limit and model disappearance switch immediately when unlocked; selected model and reason are visible | 94/100 | 100/100 | CODE/HARNESS; live provider UNVERIFIED |
| 15 | Generic failover | generic failures → consecutive counter → threshold 5 → next live model | First four generic failures report failure without changing model; the fifth switches or returns no-free-models visibly | 94/100 | 100/100 | CODE/HARNESS; live provider UNVERIFIED |
| 16 | Failover lock behavior | failure → `isModelLocked` branch → status + thrown error → ChatPanel error bubble | A pinned model fails closed and tells the user to unlock; it never silently switches | 94/100 | 100/100 | CODE; live provider UNVERIFIED |
| 17 | Rate-limit notification | switch notification → AppState observer → `MyCoderAutoFreeNotificationLogic` → `NotificationService` + transient banner | Rate-limit reason is `.error`/red and names from/to models; ordinary switches are warning-level and should not be styled as fatal | 93/100 | 100/100 | CODE/HARNESS; visual SwiftUI UNVERIFIED |
| 18 | Error persistence | stream throws → Auto Free branch catch → assistant message finished with localized error → loading reset | Failed request remains in the local session and is retryable; no false success or stuck loading state | 94/100 | 100/100 | CODE; macOS UI UNVERIFIED |
| 19 | Model metadata | live DTO → `Model.profile`/context/description → settings row/card | Live metadata is shown when supplied, with honest fallback descriptions and no guessed readiness | 92/100 | 100/100 | CODE; live metadata UNVERIFIED |
| 20 | Privacy/status disclosure | Settings provider card → endpoint/protocol/access/fallback/privacy note | User sees anonymous/no-key route, endpoint, fallback policy and warning not to send secrets | 94/100 | 100/100 | CODE; macOS visual UNVERIFIED |

## Round 56 confirmed defects and TDD fixes

### AUTO-FREE-01 / CHAT-20 — ordinary Auto Free sends dropped conversation history

The direct OpenAI-compatible branch already built prior turns through `ChatHistoryBuilder`, but the
Auto Free branch constructed only one current user message. Consequently a second prompt was sent to
the anonymous model without the previous user/assistant exchange, making ordinary multi-turn work lose
context even though the local chat visibly contained it.

A red Foundation test was written first. The new `MyCoderAutoFreeHistoryLogic` retains finished,
non-empty user/assistant turns, drops in-flight assistant placeholders and caps history at 20 turns;
edge coverage verifies `maxTurns == 0`. `ChatPanelView` now maps the local prior messages into this
contract and prepends them to the current attachment-bearing user message. Evidence: **2/2 pure
history tests passed**.

### PROV-17 — textual HTTP 429/rate-limit errors produced warning-level switches

`MyCoderAutoFreeNotificationLogic` correctly made the exact reason `"rate limit"` red, but
`MyCoderAutoFreeProvider.switchReason` returned `"1 consecutive failures"` for `MyCoderAutoFreeError.apiError("HTTP 429")`. The user therefore received a generic warning instead of the requested red rate-limit alert.

Red tests were written first for HTTP 429 and ordinary “rate limit” text, plus model/generic reason
preservation. `MyCoderAutoFreeFailoverLogic` now normalizes textual errors before notification creation;
API 429 and rate-limit messages use the red error path, while model and generic failures remain distinct.
Evidence: **2/2 pure failover-reason tests passed**.

## Source-traced controls with no additional confirmed defect

The route resolver returns `.autoFree` before Serve fallback, and `SendReadinessLogic` checks the free
catalog independently from local server health. The catalog uses an anonymous request and intersects
live IDs with the temporary free policy; the UI exposes no API-key requirement. Selection and lock
persistence are explicit, and unavailable selected models are reconciled before retry. The stream
client rejects non-free IDs and empty responses, decodes both content and reasoning deltas, and maps
429/400/403/404/410 responses to typed errors. Existing attachment and notification tests cover their
pure contracts.

The following cannot be verified in this Linux environment and remain **UNVERIFIED**: macOS SwiftUI
button hit targets and visual hierarchy, startup timing of the singleton refresh task, live OpenCode
catalog contents, anonymous request acceptance, real SSE chunk delivery, rate-limit behavior, local
session persistence on macOS, and actual request payload capture against the provider.

## Canonical user story

As a user, I can select **myCoder Auto Free**, choose and optionally lock any currently available
anonymous OpenCode free model, edit a system prompt and parameters, attach supported files/images, and
send multiple contextual turns without starting MiMo Serve or entering an API key. If the selected
model is rate-limited, unavailable or repeatedly fails, the app switches only when unlocked, persists
the new selection, shows a visible reason with red severity for rate limits, and leaves a clear error
when no safe fallback exists.

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical or UX error
• test every user behaviour again post fix
```

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Auto Free history contract | **2/2 passed** | Foundation pure logic |
| Failover reason normalization | **2/2 passed** | Foundation pure logic |
| Existing Auto Free content tests | existing suite | Foundation attachment contract |
| Existing notification tests | existing suite | Foundation severity mapping |
| Full Foundation harness | **151/151 passed** | Linux-compatible logic and prior contracts |
| Swift parser-only modified-file validation | **passed** | Syntax only; no macOS typecheck |
| Live anonymous OpenCode/SSE/model failover | **UNVERIFIED** | Network/provider availability |
| macOS SwiftUI settings/composer runtime | **UNVERIFIED** | macOS required |

| Dimension | Before Round 56 | Current verifiable score | Evidence |
|---|---:|---:|---|
| myCoder Auto Free implementation quality | 88/100 | 96/100 | Two confirmed chain defects fixed; pure red→green tests |
| myCoder Auto Free task adherence | 86/100 | 100/100 | Full controls, context, failover and notification audit |
| Target-runtime confidence | 0/100 | 0/100 | No live OpenCode or macOS execution |
