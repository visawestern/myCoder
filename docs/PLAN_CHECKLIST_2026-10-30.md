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

## 10. Классификация тестов по классам бэкендов
- [x] `BackendTaxonomy.swift` — таксономия: локальная модель, OpenAI-совместимый, веб-провайдер, opencode serve, MiMo Serve, системные; единый opt-in-флаг `liveTestsEnabled`; хелпер `ollamaReachable`.
- [x] Новый класс **`LiveLocalOllamaModelTests`** — локальная модель Ollama (health, completion, стриминг); отключается без `MIMO_LIVE_TESTS=1`.
- [x] Новый класс **`LiveOpenAICompatibleModelTests`** — удалённый OpenAI-совместимый провайдер (env `OPENAI_COMPAT_BASE_URL/API_KEY/MODEL`); без env — skipped. **STRATA не включена** (пользователь).
- [x] Существующие live-сьюты документированы в таксономии (`LiveAPIIntegrationTests` = opencode serve; `LiveIntegrationTests` = MiMo Serve; `LiveClipboardProbeTests`/`LiveImageSendVerificationTests` = системные).
- [x] Полный прогон: **3174 теста, 0 падений**.

## 11. Фиксы из живого тестирования (мерcury-3 / новый чат)
- [x] **Reasoning mercury-3**: сервер шлёт `delta.reasoning_details` (зашифрованное) — раньше терялось; теперь фиксируется честным маркером, текстовые каналы имеют приоритет.
- [x] **Фиксация всех ответов**: тексты итераций сохраняются в timeline в порядке сервера (reasoning → текст → тулы → результаты → финал); ничего не затирается.
- [x] **Кнопка «Сырой ответ»**: сообщение хранит сырые SSE-события и показывает их по кнопке.
- [x] **Кнопка «Контекст»**: всегда показывает либо пакет, либо честную причину (первый промпт / без проекта / нет соответствий / ошибка / выключено).
- [x] **Порядок в новом чате**: сессия создаётся сразу (БД + сайдбар + открытие), сообщение пишется немедленно, затем подготовка контекста и отправка.
- [x] **«Собирает контекст час»**: первый промпт (не plan) вообще не запускает сканирование индекса; сканер получил жёсткий лимит записей (30k).
- [x] **Диагностика**: `StreamDiagnostics` логирует каждый ответ/запрос ([SSE]/[UPDATE]/[REQ]/[ITER]/[TOOL]/[CTX]) по файловому флагу `/tmp/mycoder_sse_enabled`.
- [x] Подтверждено живьём: отправка в новый чат мгновенная (ack ~0s); виден реальный `[REQ]` (model=mercury-3, stream=true); подготовка не виснет; полный прогон **3187 тестов, 0 падений**.

## 12. Reasoning mercury-3: честная сводка вместо «зашифровано»
- [x] Сверено с opencode: `delta.reasoning_details` — стандартный Records-стиль провайдера (поля `type/data/format/index`), а не транспортное шифрование; запрашиваемый `reasoning.encrypted_content` мы не включаем.
- [x] Убран ложный текст «зашифровано провайдером». Теперь: текстовый reasoning (reasoning_content/thinking) имеет приоритет; иначе показывается сводка details («Рассуждение (reasoning.encrypted) · формат: mercury-v1 · id: mrt1…»).
- [x] TDD: `DirectChatRawResponseTests` обновлены.

## 13. Кликабельные пути в ответах (вне reasoning/тулов)
- [x] `MarkdownAttributedStringBuilder`: пути/имена файлов в ОБЫЧНОМ тексте (не только inline-код) получают `.chatFilePath`, если резолвятся в существующий файл/папку относительно projectRoot.
- [x] `ChatFileOpenLogic.resolveFilePath`: обрезка хвостовой пунктуации («App.swift.» → «App.swift»); голые имена без расширения допустимы, если это реальная папка.
- [x] Меню при клике: для папок — «Открыть в Finder» + «Показать в Finder»; для файлов — «Открыть с помощью» + приложения + «Показать в Finder».
- [x] TDD: `ChatFileClickablePathsTests` (5 тестов: текст/имя из root/папка/nonexistent/inline-code).

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

## 14. Автопрокрутка: без метаний и «залипания» (2026-10-31)
- [x] Причина метаний: автопрокрутка вызывалась на каждый токен стрима и слала отдельный `scrollTo` через `async` — десятки прокруток/с, каждая в устаревший фрейм якоря.
- [x] Причина «скаканий» при чтении старых сообщений: `isChatBottomVisible` обновляется с задержкой 1–2 кадра; в этом окне код дёргал обратно вниз.
- [x] Реализация (`ChatPanelView` + `ChatScrollLogic`):
  - коалесценция: максимум одна прокрутка за `minScrollInterval` (50 мс), отложенная на 16 мс;
  - подавление после колеса пользователя (`userScrollSuppression` 0.5 с, локальный `NSEvent`-монитор `.scrollWheel`);
  - пропуск прокрутки, когда якорь уже «приклеен» к низу (`anchorIsGlued`, слак 6 pt);
  - принудительная прокрутка при появлении НОВОГО сообщения (`shouldScrollAfterNewMessage`), даже если фрейм якоря не успел обновиться;
  - `.animation` убран со всего ScrollView (оставлен только у плавающей кнопки).
- [x] TDD: `ChatScrollLogicTests` (glued/дрейф/интервалы), `ChatScrollBehaviorTests` (new-message), live-проверка.
- [x] Live: правка файла в проекте — события FSEvents обновляют индекс (см. п.15); прокрутка на новом билде.

## 15. Индексация проекта: baseline один раз + событийные апдейты (2026-10-31)
- [x] Причина: у personalfairytales (159 ГБ, `.voice-runtime` 141 ГБ) индекс вообще не существовал — он строился только при открытии `@`-пикера/поиска; send не сканирует, а пустой индекс выглядел `.failed` + «⚠️ Не удалось собрать точечный контекст».
- [x] Baseline: при открытии воркспейса, если `file_index.json` нет, один фоновый bounded-скан (`PointContextIndexLogic.records`).
- [x] Событийное переиндексирование: `ProjectFileIndexEventUpdater` — по FSEvents пере-индексируются ТОЛЬКО затронутые файлы/папки (с лимитом 2000 файлов на батч); мерж в `file_index.json`.
- [x] Вотчер: накопление путей (union) вместо last-writer-wins (heartbeat `.voice-data/.worker.heartbeat` забивал дебаунс); `shouldInvalidate` игнорирует исключённые деревья.
- [x] Ограничения: `defaultExcludes` += `.voice-runtime/.voice-data/.backups/.codegraph/.pytest_cache/.mypy_cache/.ruff_cache/.repowise/.DS_Store`; байтовый бюджет скана `defaultMaxScanBytes` (400 МБ); хранимый текст записи урезан до 96 КБ (`defaultIndexSearchableTextMaxBytes`).
- [x] `ProjectFileIndexStore`: кэш декодированного индекса (по projectPath+mtime) — send больше не декодирует 122 МБ JSON (было 17.5к записей → минуты; стало 417 → 1.6 МБ).
- [x] Пустой индекс ≠ ошибка: `.failed` → `.noEvidence` (тихо, без баннера; отправка идёт исходным запросом).
- [x] TDD: `ProjectFileIndexEventUpdaterTests` (9), `ProjectFileScannerLimitTests` (байтовый бюджет + урезание текста), `ProjectFileIndexWatcherLogicTests` (excludes), `SendContextPreparationTests` (noEvidence/план).

## 16. Reasoning: только настоящий текст, никаких «зашифрованных» сводок (2026-10-31)
- [x] Удалён `DirectChatClient.reasoningDetailsSummary` и сбор `reasoningDetails` в `DirectChatStreamAccumulator`.
- [x] `visibleReasoning` = только `reasoning_content`/`reasoning`/`thinking`; пусто → `nil` (в UI блока рассуждений нет).
- [x] Сырые ответы (`rawEvents`) для кнопки «Сырой ответ» сохранены.
- [x] TDD: `DirectChatRawResponseTests` — encrypted details не показываются; текстовый reasoning показывается.
- [x] Live (mercury-3): `[ITER] reasoning_bytes=0`, `messages.reasoning` пуст.

## Live-проверка через API (2026-10-31)
- [x] Baseline pft: 417 записей, 1.6 МБ, без утечек исключённых путей.
- [x] build-чат: «какие файлы есть в корне проекта?» → `[CTX] status=compiled pack=21556B`; пакет уходит модели как text-parts; `compiled_context` прикреплён к user-сообщению; баннера нет.
- [x] plan-чат: первый промпт → `[CTX] status=compiled pack=21886B`, баннера нет.
- [x] Событийный апдейт: правка `web-app/README.md` → `[REINDEX] saved stored=417 updated=417`, хэш записи обновился.
- [x] Полный прогон: 3213 тестов (3 флаки-падения перезапущены — зелёные).
