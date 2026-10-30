# План-чеклист — 2026-10-30

Рабочий план задач текущей сессии. Статусы: ⬜ не начато, 🔵 в работе, ✅ готово.

## 1. Ошибка «The provider returned an empty response…» + ретраи
- [x] Проверить интерпретацию: пустой ответ = транзиентный сбой (модель вернула 0 токенов), а не ошибка конфигурации.
- [x] TDD: `EmptyResponseRetryPolicyTests` — пустые ответы (DirectChat/OpenCodeServe/ACP/MimoServe) ретраятся, прочие ошибки (HTTP/транспорт/parse) — нет.
- [x] Реализация: `EmptyResponseRetryPolicy` (`shouldRetry`, `withEmptyRetries`, лимит 3 суммарные попытки).
- [x] Подключить ретраи в поток отправки (прямой OpenAI-совместимый + ACP).

## 2. Режим «План»: системный промпт как в opencode
- [x] Извлечь эталонные строки plan-режима из opencode v2.1.4 (strings бинарника).
- [x] TDD: `PlanModePromptBuilderTests` — напоминание совпадает по смыслу с opencode («You are in Plan mode…», запрет изменений, «переключись на build»); build/compose не меняются.
- [x] Реализация: `PlanModePromptBuilder.resolve(agentMode:baseSystemPrompt:)`.
- [x] Подключить в прямую ветку отправки (OpenAI-совместимую). Веб-ветка (smartSend) — кандидат на следующий шаг.

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

## Тесты/сборка/коммит
- [x] Полный прогон тестов (3114; только 8 известных дорегрессионных падений).
- [x] Сборка `./build-app.sh`.
- [ ] Коммит.
