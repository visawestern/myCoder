# TODO — M1 «Маршрутизатор моделей» + SP1: что ещё не готово

> ⚠️ УСТАРЕЛО (аудит 10.11.2026): файлы из разделов 2–6 уже существуют в Sources/.
> Не создавай их заново. Сверяйся с git log (baseline `7630af5`). M1-чекилист
> закрыт, остались шаги 7–9 (полный прогон, live, коммит/пуш) + исправления аудита
> (A1–D2).

Дата: 2026-11-10. Открытые пункты `docs/PLAN_CHECKLIST_2026-11-09.md`:
**M1 (строки 227–308)** и **SP1** (добавлен в конец чеклиста). T1 закрыт.
C1–C6, U1–U7, P1 закрыты и запушены (`d9ea177`).

## Уже готово (НЕ переделывать)

- [x] Ядро: `ModelRouting.swift` (ModelRole ×9, ModelAssignment, ModelRoutingConfiguration,
      ModelRoutingError, ModelRouteResolver, ModelRoutingStore + projectConfiguration/chatConfiguration).
- [x] Граф хода: `TurnRouteGraph.swift` (build/chainPreview, runCollecting, журнал при провале/отмене,
      ReviewResponseParser, TurnRoutePrompts, ModelRouteJournalStore 50/сессию).
- [x] Транспорт ролей: `RoleModelTransport.swift` (RoleTransportContext, RoleTransportResolver,
      RoutedImagesPolicy, RoleRequestExecutor — openAI/serve/mimo/ACP/web/unresolved, без скрытого fallback).
- [x] AppState-мост: `AppState+Routing.swift`; @Published-поля в MyCoderApp.swift.
- [x] `RoutedTurnService.swift` — Snapshot/Status/Outcome + RoutedTurnLogic + RoutedTurnExecutor.
- [x] Wiring `ChatPanelView.swift`: routed-ветка ДО SendRouteGuard, runRoutedTurn,
      summaryTransport(+sessionID), supportsLocalHistoryCompaction(perRole→true),
      subagent через routedSubagentTransport, planner complete:, reloadModelRouting в 3 хуках.
- [x] `ChatPanelView+Routing.swift`: buildRoutedTurnSnapshot, reloadModelRouting,
      routedCompactionTransport, routedPlanningComplete, routedSubagentTransport.
- [x] `TurnContextPlanningService.plan(complete:)` passthrough.
- [x] `AppState+Database.deleteSessionInDatabaseUI` — clear журнала + chat-override.
- [x] `ModelRoutingMenu.swift` + вставка в `InputControls.swift`.
- [x] Тесты wiring-слоя: RoutedTurnLogicTests (12) + RoutedTurnExecutorTests (5) +
      ModelRoutingWiringTests (8) — GREEN.
- [x] **SP1** — единая дисциплина кода `HarnessPromptQuality.codeDiscipline` на ВСЕХ маршрутах
      (дедуп + рефактор: native через collaborationCore, web/OpenAI через ToolInstructionGuide).
      2 новых теста в HarnessPromptQualityTests; пункт добавлен в конец PLAN_CHECKLIST.
- [x] `swift build` — GREEN.

## Осталось сделать

### 7. Сборка и полный прогон тестов
- [ ] `swift build` → GREEN (подтверждено).
- [ ] `swift test --no-parallel` → полный прогон GREEN
      (Git-таймауты GitPushUpstreamTests/GitRepositoryTests — известные флаки окружения,
      не регрессии; при падении перепроверить отдельно).

### 8. Живой прогон (обязателен по чеклисту M1)
- [ ] `ollama serve` в background (агент стартует сам; приложение провайдеров не стартует —
      это ограничение приложения, не агента).
- [ ] Health: `curl http://127.0.0.1:11434/api/tags` (модели установлены: gemma4,
      speakeasy-gemma4-e2b-cpu, kimi-k2.5/k2.6, deepseek-v4-flash, gemini-3-flash-preview, glm-5.1, minimax-m2).
- [ ] Env-gated тест `MYCODER_LIVE_ROUTING=1 swift test --filter RoutingLive` (пропускается offline):
  - [ ] цепочка plan model1 → execution model2 → review model3
        (LocalProviderConfig(id:"live-ollama",kind:.ollama,port:11434,...) → openAICompatible
        http://127.0.0.1:11434/v1) через RoutedTurnExecutor;
  - [ ] отдельный прогон TurnRouteRunner с custom graph [.execution,.review,.finalResponse];
  - [ ] assertions: entries.count, ФАКТИЧЕСКИЕ modelID на узел, isCompleted,
        статус completed ИЛИ reviewLimitReached, непустой текст.
- [ ] Vision-live: честно доложить (catalog vision для ollama-моделей не подтверждён —
      если vision-fallback не проверить вживую, так и написать).

### 9. Закрытие
- [ ] Чеклист `docs/PLAN_CHECKLIST_2026-11-09.md` M1 (227) → [x] с деталями (образец — T1).
- [ ] Отметить выполненные пункты этого TODO-файла.
- [ ] Коммит (T1 + M1 + SP1) + пуш в `main` (последний запушенный `d9ea177`).
      Git-безопасность: перед пушем убедиться, что дерево чистое/закоммичено (см. collaborationCore).
- [ ] Итоговый доклад: что закрыто, live-результаты (фактические модели из журнала),
      что пользователю проверить в GUI.

## Требования к каждому шагу (напоминание)

- TDD: сначала падающий тест → реализация → зелёный прогон.
- Новые файлы ≤600 строк; функции с комментариями (вход/выход/что делает/зависимости).
- Без заглушек/фейков вне тестов; моки только в тестах и помеченные.
- Запрещён скрытый cross-provider fallback; любая недоступность — явная честная ошибка.
