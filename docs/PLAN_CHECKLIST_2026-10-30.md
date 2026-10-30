# План-чеклист — 2026-10-30

Рабочий план задач текущей сессии. Статусы: ⬜ не начато, 🔵 в работе, ✅ готово.

## 8. Исправление всех известных падений тестов (8 шт.)
- [x] `taskCreateListUpdateRoundTrip` — парсинг id из формата «## Session checklist [pending] <id>: …»; аргумент `task_id` → канонический `id` по схеме.
- [x] `taskUpdateMissingIdErrorsHonestly` — текст ошибки теперь называет оба инструмента: «use task_list or todo_read to see ids».
- [x] `preambleChunksStayUnderByteBudget` — преамбула разрослась до 4047 Б (порог ~3737 Б) и резалась на 2 части; сокращена (identity/rules/policy) при сохранении всех гарантий.
- [x] `firstMessagePrependsPreamble` — следствие того же: первый ход снова один чанк с тулом-контрактом.
- [x] `ModelSettingsPremiumTests`/`SettingsIntegrationTests` — маркеры исходника обновлены под актуальный UI (`ForEach(familyGroups` вместо старого `displayModels`; фильтр/сортировка/скролл/удаление сохранены).
- [x] Полный прогон: **3118 тестов, 0 падений**. Коммит `4e262f2`.

## 9. Ревью покрытия: новые тесты для непокрытых типов
- [x] Скрипт: 1020 типов в Sources; 428 не упоминались в тестах (в основном UI-вью/DTO; выбраны типы с логикой).
- [x] Новые тестовые файлы (все зелёные):
  - `UsageStatisticsAggregatorTests` — санитизация стоимости, нормализация имён, агрегаты, фаворит, активные дни, итоги, costLabel;
  - `StorageResetLogicPlanTests` — планы сброса, дедупликация, сводка, нормализация id проекта;
  - `ChunkedSendSequencerTests` — стратегия по маршруту, пейлоады с маркерами частей;
  - `WebChatSignalBoxesTests` — retry/approval/completion сигналы, LimitStabilityBox, RestartCountBox;
  - `WebSessionLogicInferenceTests` — captcha/лимит/loggedOut/connected + шаги восстановления;
  - `OutputAccumulatorGitPublishTests` — one-time код, аргументы repo, описания ошибок;
  - `UserMessageNavigatorLogicTests` — фильтрация, превью, номера, шаги;
  - `MCPHealthCheckLogicTests` — пробы http/stdio, разрешение PATH, статусы;
  - `ProjectDeletionExecutorTests` — безопасность и реальное удаление;
  - `ErrorDescriptionTests` — описания ошибок (AppAction/Keychain/Snapshot/Export/провайдеры);
  - `OpenCodeSessionStoresTests` — хранилища сессий serve.
- [x] Полный прогон: 3146 тестов; флейки сетевых/таймерных тестов под нагрузкой (сборка Chromium) — при повторе зелёные.
- [x] `MessageTypeEnumTests` — связка MessageType↔AgentMode, роли, действия (добавлено).
- [x] Замер покрытия (llvm-cov, `swift test --enable-code-coverage`, 3149 тестов, только Sources):
  - Services: **70.0% функций / 69.8% строк**;
  - Models: **60.8% / 68.3%**;
  - Theme: 60.8% / 81.7%;
  - App: 39.8% / 34.5%;
  - Views: 2.4% / 1.4% (UI не покрыт юнит-тестами);
  - **ИТОГО: 40.8% функций / 32.2% строк**.
- [x] Второй батч: `FileSnapshotManagerTests` (DI пути + фикс `invalidMetadata` вместо сырого NSError), `FileDropLogicTests` (pasteboard/legacy/dedup), `DirectWebAPIClientLogicTests` (SSE/cookies/token), `MessageTypeEnumTests`.
- [x] Повторный замер (3168 тестов): Services **70.5% / 70.4%**, Views 4.7% / 3.3%, **ИТОГО 42.0% функций / 33.6% строк**.

## 1. Ошибка «The provider returned an empty response…» + ретраи
- [x] Проверить интерпретацию: пустой ответ = транзиентный сбой (модель вернула 0 токенов), а не ошибка конфигурации.
- [x] TDD: `RequestRetryPolicyTests` — пустые ответы (DirectChat/OpenCodeServe/ACP/MimoServe) и HTTP 408/429/500/502/503/504 ретраятся; прочие ошибки (401/403/404, транспорт, parse) — нет; до 10 суммарных попыток; пауза экспоненциальная с потолком 60с.
- [x] Реализация: `RequestRetryPolicy` (заменил `EmptyResponseRetryPolicy`).
- [x] Подключить ретраи в поток отправки (прямой OpenAI-совместимый + ACP).

## 2. Режим «План»: системный промпт как в opencode
- [x] Извлечь эталонные строки plan-режима из opencode v2.1.4 (strings бинарника).
- [x] TDD: `PlanModePromptBuilderTests` — напоминание совпадает по смыслу с opencode («You are in Plan mode…», запрет изменений, «переключись на build»); build/compose не меняются.
- [x] Реализация: `PlanModePromptBuilder.resolve(agentMode:baseSystemPrompt:)`.
- [x] Подключить в прямую ветку отправки (OpenAI-совместимую). Веб-ветка (smartSend) — кандидат на следующий шаг.
- [x] План не показывает запросы на безопасность: `PlanModeToolPolicy` (TDD) — мутирующие тулы (write/edit/patch) отклоняются без промпта с текстом-отказом, read-only тулы выполняются.

## 2а. Режим «План»: сборка контекста
- [x] `SendContextPreparationLogic.prepare(isPlanMode:)` — план собирает контекст даже на первом промпте.
- [x] TDD: `planModeCompilesContextOnFirstTurn` — пакет с цитатами собирается.
- [x] `ChatPanelView` передаёт `isPlanMode: agentMode == .plan`.

## 3–5. Правила сборки контекста
- [x] TDD: `SendContextPreparationFirstTurnTests`:
  - первый промпт в чате (с проектом и без) — контекст НЕ собирается, `.firstTurn`;
  - со второго промпта контекст проекта = изученные данные + история чата (`.compiled`, секция «История чата»);
  - чат без проекта: предыдущие сообщения — контекст (`.chatContext`).
- [x] Реализация: `SendContextStatus.firstTurn/.chatContext`, `TurnContextCompiler` (история + `compileChatHistory`), `SendContextPreparationLogic.prepare(priorTurns:)`.
- [x] Подключить `priorTurns` в `ChatPanelView` (до подготовки сессии) и обновить существующие тесты `SendContextPreparationTests`.

## 6. Сайдбар: видно, какой чат открыт в активном окне
- [x] TDD: `SidebarSelectionLogicTests` — выбранный чат совпадает по id (проектные и без-проектные), nil/пустой id не подсвечивают.
- [x] Реализация: `SidebarSelectionLogic.isSelected(sessionID:selectedSessionID:)`; применена в `SessionTaskRow` и `ProjectlessChatRow`; у без-проектных чатов добавлена фоновая подсветка (как у проектных).

## 7. Effort-селект в панели отправки
- [x] Причина: `availableVariants` брал варианты только из ответа провайдера; mercury-3 их не сообщает, хотя каталог метаданных знает efforts (low/medium/high).
- [x] TDD: `ProviderVariantCatalogFallbackTests` — серверные варианты имеют приоритет; fallback на каталог для mercury-3; неизвестная модель без вариантов.
- [x] Реализация: fallback на `ModelMetadataCatalog` в `ProviderSettingsLogic.availableVariants` → селект появляется.

## Тесты/сборка/коммит
- [x] Полный прогон тестов (3118; только 8 известных дорегрессионных падений).
- [x] Сборка `./build-app.sh`.
- [x] Коммит `d3ce4f0`.
