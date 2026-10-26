# Причинно-следственная карта

Дата: 2026-08-11. Область: все функции, которые участвуют в отправке,
выборе provider/model, web discovery/effort и сохранении первой неудачной
сессии.

## Chain A: myCoder Auto Free send

```text
ContentView.task
  -> AppState.loadCustomProviders
  -> AppState.validateAndReconcileSelections
  -> AppState.selectProvider(mycoder-auto-free)
  -> MyCoderAutoFreeStore.provider.selectedModel
  -> AppState.effectiveSelectedModel
  -> SendReadinessLogic.sendValidationError
  -> SendRouteResolver.route(.autoFree)
  -> MyCoderAutoFreeStore.selectModel
  -> MyCoderAutoFreeStore.streamChat
  -> MyCoderAutoFreeClient.chatCompletion
  -> MessageStore assistant deltas
  -> finished assistant message
```

**Result:** PASS by tests. Network response remains live-QA.

## Chain B: Web model discovery

```text
WebProviderLoginView.capture
  -> WebProvidersSection.persistCookies
  -> AppState.refreshWebModels
  -> WebModelDiscovery.discover
  -> BrowserAutomationBridge.exists/click/readModelItems/readText
  -> WebModelListParser.parse
  -> ChatGPT feature filter / Qwen selector merge
  -> WebProviderStore.upsert
  -> WebProviderConnectivity.models
  -> AppState.modelsForSelectedProvider
  -> ModelSelectorMenu
```

**Result:** PASS by parser/route tests; authenticated WebKit is live-QA.

## Chain C: Web effort

```text
WebProviderCard refresh effort
  -> AppState.refreshWebEffort
  -> WebModelDiscovery.discoverEffort
  -> split vendor selectors
  -> bridge exists/click/readText
  -> WebModelListParser.parseEffortLevels
  -> WebProviderStore.upsert(discoveredEffortLevels)
  -> WebProviderCard effort status
  -> WebChatDriver.injectModelAndEffort
  -> vendor effort option click
```

**Result:** PASS by code; live selector behavior remains live-QA.

## Chain D: Failed first request

```text
sendMessage
  -> readiness/connection validation
  -> recordRejectedSend on preflight failure
  -> AppState.prepareLocalSessionForSend when workspace exists
  -> DatabaseBridge.createSession(project-scoped)
  -> MessageStore.currentSessionID
  -> DatabaseBridge.saveMessage(user)
  -> DatabaseBridge.saveMessage(assistant error)
  -> delayed selection/sidebar context
```

```text
sendDirectly
  -> route resolution
  -> prepareSessionBeforeAppending
  -> local/remote session identity before first append
  -> save user message + assistant placeholder/error
  -> update assistant failure visibly
```

**Result:** PASS by `SendPersistenceLogicTests`, ChatPanel source contract, and 88/88 Foundation harness tests. macOS DB relaunch and provider runtime remain UNVERIFIED.

## Chain E: Provider readiness

```text
InputControls send button
  -> displayed readiness reason
  -> effective model/provider
  -> SendReadinessLogic.canSendMessage
  -> connectionValidationError
  -> route resolver
  -> visible error or request
```

**Result:** PASS. No silent disabled send remains in the tested path.

## Remaining external boundary

The following cannot be proven by local tests: real WKWebView DOM selectors,
third-party login cookies, ChatGPT's current one-model page, Qwen's current
full model list, and actual MiMo API response. They remain `PARTIAL/live-QA`.

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical error or ux error
• test every user behaviour again post fix
```
