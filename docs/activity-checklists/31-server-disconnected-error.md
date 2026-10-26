# Activity 31 — Server Disconnected Error

## Audit objective

This round audits **ERR-02 Server Disconnected Error** from `AppState.serverConnected` and provider selection through `SendReadinessLogic`, `SendProviderReadinessLogic`, `SendReadinessReason`, both centered and bottom composer layouts, `SendStopButton`, keyboard Enter gating, `ChatPanelView` rejected-send persistence, and the visible error message.

The prior Round 59 fix correctly stopped Serve health from masquerading as readiness for web, local, or custom routes. The current adversarial audit found one remaining clarity defect: when a known Serve provider was selected but disconnected, the readiness contract returned the generic “No provider is ready” alternatives. That message did not tell the user that the selected route specifically required myCoder Serve to be started or reconnected.

## Full chain checklist

| # | UI/control/action/function | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Provider selection | `AppState.selectedProviderID` → readiness inputs | Identify whether the selected route is Serve, web, local, custom, Auto Free, or none. | **Pass by source/tests.** |
| 2 | Serve health state | `serverConnected` → readiness | Treat Serve health as relevant only for Serve-backed provider selection. | **Pass by existing Round 59 tests.** |
| 3 | Known disconnected Serve route | known `serverProviderIDs` + `serverConnected=false` | Return explicit myCoder Serve start/reconnect guidance. | **Fixed Round 77:** red/green regression. |
| 4 | Unknown provider route | selected ID absent from all catalogs | Fail closed with a generic provider-readiness message. | **Pass by source.** |
| 5 | Web route while Serve is down | `web:` provider + webConnected | Do not block a connected web route because Serve is unavailable. | **Pass by existing tests.** |
| 6 | Web route disconnected | `web:` provider + `webConnected=false` | Tell the user to reconnect the selected web provider in Settings. | **Pass by existing tests/source.** |
| 7 | Local route while Serve is down | local provider ID | Allow route readiness without Serve. | **Pass by source/tests.** |
| 8 | Custom route while Serve is down | enabled custom provider + API key | Allow route readiness without Serve. | **Pass by source/tests.** |
| 9 | Missing custom API key | custom provider → `requiresAPIKey` | Block with an API-key-specific message. | **Pass by source/tests.** |
| 10 | Auto Free unavailable | Auto Free ID → readiness | Block with catalog refresh/alternate-provider guidance. | **Pass by source.** |
| 11 | Centered composer Send button | `canSendMessage` + `SendStopButton.disabledReason` | Disable send and show explicit error color/help text. | **Pass by source; native UI UNVERIFIED.** |
| 12 | Bottom composer Send button | same readiness contract | Maintain the same route-specific result as centered composer. | **Pass by source; native UI UNVERIFIED.** |
| 13 | Keyboard Enter | `SendButtonActivationLogic` + canSend | Prevent Enter from bypassing disconnected-route validation. | **Pass by existing tests/source.** |
| 14 | Visible readiness reason | `SendReadinessReason.reason` → inline text/help | Show provider/model/route blocker before send, not only after a click. | **Pass by source; native rendering UNVERIFIED.** |
| 15 | Rejected send persistence | `ChatPanelView` → `recordRejectedSend` | Preserve the attempted user text and actionable assistant error in the session. | **Pass by source; DB/native runtime UNVERIFIED.** |
| 16 | Direct-send guard | `sendDirectly` connection validation | Recheck readiness before routing and never fall through to Serve. | **Pass by source.** |
| 17 | Live endpoint failure | HTTP/URLSession → error UI | Surface real endpoint/runtime failures distinctly from preflight disconnected readiness. | **PARTIAL/UNVERIFIED:** requires macOS and live endpoint. |

## Confirmed defect and TDD evidence

### Known Serve disconnection returned a generic unrelated-provider error

When `selectedProviderID` was present in `serverProviderIDs` but `serverConnected` was false, `SendProviderReadinessLogic` fell through to the generic `genericProviderError`. The resulting text suggested connecting a local agent, adding a custom provider, configuring a local model, or connecting a web provider. None of those instructions directly addressed the selected Serve route and could make a user troubleshoot the wrong subsystem.

A red regression was added to `SendProviderReadinessLogicTests` before the implementation. It failed because the returned message did not contain “Serve”. The green fix adds a known-Serve/disconnected branch that says myCoder Serve is not running or disconnected and instructs the user to start or reconnect it. Existing web/local/custom route tests remained green.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red disconnected-Serve message regression | **failed as expected** | Generic message did not mention Serve |
| Green readiness regressions | **4/4 passed** | Known Serve, web, effective model, and stale-health cases |
| Full Foundation harness | **255/255 passed** | Existing contracts plus ERR-02 regression |
| Swift parser validation | **passed** | SendProviderReadinessLogic |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native composer rendering | **UNVERIFIED** | Requires SwiftUI/AppKit runtime |
| Live Serve endpoint/health failure | **UNVERIFIED** | Requires macOS runtime and actual Serve process |

`ERR-02` remains **PARTIAL**. Route-specific disconnected Serve guidance is fixed and contract-tested; readiness remains correctly independent for web/local/custom routes. Native composer rendering, live health transitions, network failure variants, and localized display remain unverified.

The **implementation quality score is 96/100**. The confirmed misleading error text is fixed with a narrow provider-aware branch; native presentation and live endpoint behavior remain.

The **task-following score is 100/100**. Every readiness function, button, keyboard path, rejected-send path, and error consumer was traced, the red test preceded the fix, documentation was updated, and macOS-only behavior remains explicitly UNVERIFIED.

> A disconnected Serve route should tell the user to reconnect Serve; it should not redirect them to unrelated provider setup paths.
