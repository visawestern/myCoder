# Полный checklist качества функций

Статусы: `PASS` = функция проверена цепочкой и тестом; `PARTIAL` = внешний
ресурс отсутствует; `FIXED` = найден разрыв и исправлен этим циклом.

## myCoder Auto Free

| Функция | Проверка | Качество |
|---|---|---|
| `MyCoderAutoFreeClient.listModels` | live catalog intersects eligible temporary free IDs | PASS |
| `MyCoderAutoFreeClient.chatCompletion` | anonymous OpenCode Zen SSE request without API key | PASS by code; live network pending |
| `MyCoderAutoFreeStore.refreshModels` | unavailable catalog fails closed; no synthetic paid fallback | PASS |
| `MyCoderAutoFreeStore.selectModel` | selected live free model persists | PASS |
| `MyCoderAutoFreeStore.streamChat` | selected model, failover and rate-limit status | PASS by code; live network pending |
| `MyCoderAutoFree system prompt` | saved prompt precedes user content | PASS |
| `AppState.selectProvider` | built-in provider selects only verified free model | FIXED/PASS |
| `AppState.effectiveSelectedModel` | resolves Auto Free/web model | PASS |
| `SendRouteResolver.route` | Auto Free resolves `.autoFree` | PASS |
| `MyCoderAutoFreeNotificationLogic` | rate limit is visible error notification | PASS |
| `MyCoderAutoFreeClient.shouldSwitch` | immediate rate/model fallback or five-failure switch | PASS |
| `ChatPanelView` Auto Free attachments | image data URLs and readable text files become content parts; unsupported binary files show a warning | FIXED/PARTIAL — Round 52; live request capture pending |

## Readiness and persistence

| Функция | Проверка | Качество |
|---|---|---|
| `connectionValidationError` | provider-specific connection rules | PASS |
| `sendValidationError` | empty model/provider guidance | PASS |
| `canSendMessage` | text + model + connection gate | PASS |
| `SendReadinessReason.reason` | first actionable error | PASS |
| `ChatPanelView.sendMessage` | preflight and dispatch | PASS |
| `ChatPanelView.sendDirectly` | effective model and route | FIXED/PASS |
| `AppState.prepareLocalSessionForSend` | creates project-owned session before first append without early selection | FIXED/PASS — Round 51 |
| `ChatPanelView.recordRejectedSend` | stores user/error pair on preflight failure | FIXED/PASS — Round 51 |
| `ChatPanelView.prepareSessionBeforeAppending` | binds local/remote session before first append | FIXED/PASS — Round 51 |
| `DatabaseBridge.createSession` | owns correct project DB | PASS |
| `DatabaseBridge.saveMessage` | persists user/error pair | PASS |

## Web configuration and connectivity

| Функция | Проверка | Качество |
|---|---|---|
| `WebProviderConfig.init` | no guessed model before discovery | FIXED/PASS |
| `WebProviderConfig.allModels` | combines configured model sources | PASS |
| `WebProviderConfig.addCustomModel` | trims/deduplicates | PASS |
| `WebProviderConfig.removeCustomModel` | removes configured item | PASS |
| `WebProviderStore.save/load` | Codable persistence | PASS |
| `WebProviderStore.upsert` | replaces by ID | PASS |
| `isConnected` | ToS + non-expired cookies | PASS |
| `providerOptions` | only connected web providers | PASS |
| `models(for:)` | no catalog guess fallback | FIXED/PASS |
| `connectionSummary` | reports model count/transport | PASS |

## Discovery and parser

| Функция | Проверка | Качество |
|---|---|---|
| `WebProviderCatalog.loadBundled` | bundle/repo resource resolution | PASS |
| `selectors/models` | returns vendor catalog data | PASS |
| `WebModelDiscovery.canRefresh` | selector availability | PASS |
| `WebModelDiscovery.discover` | open/read/merge model options | FIXED/PASS |
| `WebModelDiscovery.discoverEffort` | tries each selector independently | FIXED/PASS |
| `discoverFeatureModes` | vendor feature extraction | PASS by code, live-QA |
| `discoverThinkingLevels` | Qwen effort extraction | PASS by code |
| `WebModelListParser.parse` | splits, normalizes, deduplicates | PASS |
| `normalize` | rejects UI chrome | PASS |
| ChatGPT model filter | excludes research/image/canvas/actions | FIXED/PASS |
| `parseEffortLevels` | maps vendor labels | PASS |
| `normalizeEffort` | maps low/medium/high | PASS |
| `updated` | replaces discovered model list | PASS |

## Web driver

| Функция | Проверка | Качество |
|---|---|---|
| `runTurn` | model/effort -> send -> loop -> final | PASS by mocks |
| `sendPossiblyChunked` | chunk/continuation protocol | PASS |
| `sendMessage` | type then click | PASS by mocks |
| `restartSessionWithCarryOver` | preserves context on limit | PASS |
| `awaitResponse` | stop disappears + stable text | PASS |
| `readLatestResponse` | primary/fallback selectors | PASS |
| `checkInterruptions` | captcha/logout state | PASS |
| `injectModelAndEffort` | applies selected controls | PASS by mocks, live-QA |
| `startNewSession` | clicks vendor new-chat text | PASS |
| `getCurrentChatID` | parses chat/c URL | PASS |
| `selectModel/selectMode/selectThinking` | vendor-specific controls | PASS by mocks, live-QA |
| `modelSelector/effortLabel` | resolves catalog/labels | PASS |
| `antiBanDelay` | bounded jitter | PASS |

## UI handlers

| Функция | Проверка | Качество |
|---|---|---|
| `addVendor/remove/save` | config lifecycle | PASS |
| `persistCookies` | saves session then refreshes models | PASS by code |
| `refreshModels/refreshEffort` | calls AppState and reloads store | PASS by code |
| `WebProviderCard.body` | status/buttons/effort visible | PASS by code |
| `WebProviderLoginView.capture` | captures cookies and dismisses | PARTIAL, live WebKit |
| `WebViewRepresentable` | attaches and loads URL | PARTIAL, live WebKit |
| `WebChatWebViewHost` | keeps chat webview attached | PASS by code, live WebKit |

## Final gate

- [x] Targeted provider/model tests pass.
- [x] Failed first-send persistence regression passes.
- [x] Full `swift test` passes: 1858 tests, 265 suites.
- [x] Live Kimi model menu verified: K3, K3 Swarm.
- [x] Live Qwen refresh verified: Qwen3.7-Max, Qwen3.7-Plus, Qwen3.8-Max.
- [ ] Live ChatGPT discovery remains PARTIAL: page/cookies work, model result did not appear.

```text
/goal go over every single feature in this file create a user story with expected behaviour based on the code keep a single canonical spreadsheet tracking the features status
• when done switch loop to testing every user story and documenting all errors
• when done fix every logistical error or ux error
• test every user behaviour again post fix
```
