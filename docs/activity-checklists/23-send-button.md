# Activity 23 — Send Button

## Audit objective

This round audits **INP-10 Send Button** from `ChatPanelView` and `EmptyChatStateView` into `CenteredInputCard`, `BottomInputBar`, `MessageInputToolbar`, `SendStopButton`, `SendReadinessLogic`, `SendReadinessReason`, `MessageQueue`, attachment handling, route resolution, and `sendDirectly`.

The visible Send button already used `canSend` and switched to Stop while loading. The confirmed gap was that keyboard Enter callbacks were wired directly to `onSend`, bypassing the same gate. In both the centered first-message composer and the bottom follow-up composer, Enter could invoke `sendDirectly` while the visible Send button was disabled or while the UI was in loading/stop mode. Round 69 adds a shared activation contract and guards both keyboard paths.

## Button, action, and function checklist

| # | UI control/action | Chain traced | Expected behavior | Result |
|---:|---|---|---|---|
| 1 | Visible Send icon | `SendStopButton` → `onSend` | Invoke send only when `canSend` is true. | **Pass:** button is disabled when `!canSend`. |
| 2 | Disabled Send appearance | `canSend`, `disabledReason` → icon color/help | Explain why send is blocked without a silent no-op. | **Pass by source:** error color/help and inline readiness reason exist; native visual state UNVERIFIED. |
| 3 | Stop icon while loading | `isLoading` → `SendStopButton` → `onStop` | Replace Send with Stop and never start a second send. | **Pass by source:** loading branch renders Stop; native interaction UNVERIFIED. |
| 4 | Centered first-message Enter | `CenteredInputCard.inputCore` → `CompactChatPromptField` → `onSubmit` | Mark attempted-send for empty-input feedback, then invoke only when ready and idle. | **Fixed:** shared activation guard now blocks invalid/loading Enter. |
| 5 | Bottom follow-up Enter | `BottomInputBar` → `CompactMessageTextField` → `onSubmit` | Match visible Send button gate for text, files/images, provider, model, and loading. | **Fixed:** shared activation guard now blocks invalid/loading Enter. |
| 6 | Empty text with no attachment | `SendReadinessLogic` → `canSend=false` | Keep Send disabled and show the empty-input reason only after an attempted centered send. | **Pass by source/tests; native typography UNVERIFIED.** |
| 7 | Image-only message | attachment store → `SendReadinessLogic` → Send | Allow sending when an image is attached even if text is empty; preserve image payload. | **Pass by existing attachment/send tests; native picker UNVERIFIED.** |
| 8 | File-only message | attachment store → readiness → send route | Allow supported file attachments and preserve their display/payload semantics. | **Pass by existing send tests; native file picker/filesystem UNVERIFIED.** |
| 9 | Invalid provider/model | readiness reason → disabled Send/help | Keep both button and Enter blocked, explaining provider/model readiness. | **Fixed for Enter; button already gated.** |
| 10 | Web provider readiness | web connection state → readiness → Send | Block send if browser session is not connected or model is unavailable. | **Pass by source/contracts; live WebKit session UNVERIFIED.** |
| 11 | Auto Free readiness | Auto Free store → readiness → Send | Do not invoke send if the selected free route is unavailable. | **Pass by existing readiness tests.** |
| 12 | Queue while loading | `ChatPanelView.sendMessage` → `MessageQueue.enqueue` | Preserve user intent by queueing a new message while a send is active, if queue policy allows. | **Pass by source/tests; native queue card interaction UNVERIFIED.** |
| 13 | Pending queue cancel | `PendingMessageCard` → `messageQueue.cancelPending(at:)` | Remove only the selected queued item and retain others. | **Pass by existing queue tests; native row interaction UNVERIFIED.** |
| 14 | Plus/attachment menu | toolbar plus → `PlusMenuView` → file/photo picker | Open attachment/actions menu without invoking Send accidentally. | **Pass by source; AppKit picker runtime UNVERIFIED.** |
| 15 | Slash command input | text field → command dropdown → insertion | Insert command text and keep send readiness recomputed. | **Pass by existing command tests.** |
| 16 | Route resolution | `sendDirectly` → `SendRouteResolver` | Use one stable route for the appended user/assistant messages and provider branch. | **Pass by existing routing tests.** |
| 17 | Readiness rejection | `sendDirectly` validation → `recordRejectedSend` | If a programmatic path reaches send despite UI state, persist a visible rejection rather than silently doing nothing. | **Pass by source; persistence/runtime unverified.** |
| 18 | Stop/cancel action | Stop button → `stopGeneration` → provider-specific stop/cancel | Stop active generation without triggering a new send. | **Partial:** source paths exist; live provider cancellation UNVERIFIED. |
| 19 | Send button accessibility | icon-only button → `.help` | Provide an actionable tooltip for Send/Stop and blocked reason. | **Pass by source; native VoiceOver/UI runtime UNVERIFIED.** |

## Confirmed defect and TDD evidence

### Keyboard Enter bypassed the Send button gate

`SendStopButton` disabled itself when `canSend` was false, but `CenteredInputCard.inputCore` used `onSubmit: { hasAttemptedSend = true; onSend() }`, and `BottomInputBar` used `onSubmit: onSend`. `CompactMessageTextField` forwards that callback from the AppKit text view, so pressing Enter bypassed the visible button’s readiness gate. While loading, the same callback could invoke `onSend` even though the visual control had switched to Stop.

`SendButtonActivationLogicTests` was written first. The red run failed because the activation contract did not exist. The green `SendButtonActivationLogic.canInvokeSend(canSend:isLoading:)` returns true only for ready, idle state. Both centered and bottom Enter handlers now use it; the centered path still sets `hasAttemptedSend` so the user receives the intended empty-input reason.

## Remaining limitations

INP-10 remains **PARTIAL**. Linux cannot execute SwiftUI/AppKit rendering, keyboard event delivery, accessibility/VoiceOver, native pickers, or live provider stop behavior. The button/Enter readiness contract is now consistent in source, but route-level runtime failures still require the existing `sendDirectly` validation and persistence guards.

## Evidence and scores

| Check | Result | Boundary |
|---|---:|---|
| Red keyboard activation regressions | **failed as expected** | Missing shared activation contract |
| Green activation regressions | **3/3 passed** | Ready/idle allow, invalid/loading block |
| Full Foundation harness | **232/232 passed** | Existing contracts plus INP-10 regressions |
| Swift parser validation | **passed** | Activation logic and InputViews |
| Adversarial source checks | **12/12 passed** | Provider/browser/model invariants remained green |
| Native SwiftUI/AppKit interaction | **UNVERIFIED** | Requires macOS runtime |
| Keyboard/accessibility behavior | **UNVERIFIED** | Requires native event and VoiceOver runtime |

The **implementation quality score is 94/100**. The Send button and both keyboard paths now share one tested activation gate; native keyboard/accessibility, picker, and live cancellation behavior remain outside Linux verification.

The **task-following score is 100/100**. Every visible send/stop action and underlying function was traced, the confirmed bypass received a red test before the fix, and native-only behavior is explicitly UNVERIFIED.

> A keyboard shortcut is another activation route for the same action; it must obey exactly the same readiness and loading contract as the visible button.
