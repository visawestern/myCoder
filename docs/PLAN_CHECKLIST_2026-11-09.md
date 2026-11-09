# План-чеклист 2026-11-09: дедупликация контекста + UX-баги

> Статус: ведётся. Раунд 1 завершён и запушен (`a8cce4a`).
> Правила: TDD (тест сначала), файлы ≤600 строк, функции с комментарием
> (вход/выход/что делает/зависимости), коммит+пуш после каждого раунда.

---

## Раунд 1 (завершён ✅): дедупликация собранного контекста

### Что проверено
- `ContextDeduplication.deduplicate` вызывается в `TurnContextCompiler.compile`
  перед финальным `render` — т.е. дедуп применяется к итоговому пакету,
  который уходит модели (путь: `SendContextPreparationLogic.prepare` →
  `TurnContextCompiler.compile` → `ContextDeduplication`).
- Покрытие тестами (17 тестов: 13 юнит + 4 интеграционных) подтверждает:
  - один блок на файл (кандидат + «— зависимость» одного пути);
  - точный повтор содержимого;
  - строки из файловых блоков не повторяются в истории/памяти;
  - «Запрос» пользователя неприкосновенен;
  - разные файлы с общим boilerplate остаются оба;
  - смысловой дубль (Jaccard ≥0.85 / вхождение) в повествовательных секциях;
  - порядок секций после дедупа сохраняется.

### Найденные и исправленные дефекты
1. **Cтроки с номерами не дедуплицировались.** `ContextMaterializer` рендерит
   код как `42 | let x = …`, а диалог цитирует ту же строку без номера.
   Фильтр «строк из файлов» не находил совпадений → дубль «из диалога и из
   файлов» оставался. Исправлено: `ContextDeduplication.stripLineNumberPrefix`
   снимает префикс `N | ` и запоминает обе формы.
   Тесты: `numberedFileLinesMatchNarrative`, `fullyRedundantNarrativeDropped`
   (были красные → стали зелёные).
2. **Цитаты выброшенных секций оставались в пакете.** После дедупа фильтр
   был только по пути, поэтому цитата секции «path — зависимость» (отброшена
   как дубль файла) выживала. Исправлено: цитаты сверяются с заголовками
   реально включённых блоков (`keptBlockHeaders`).
   Тест: `candidateAndDependencySameFileSingleBlock`.

### Регрессия
- Полный прогон: 3750 тестов, падают только 2 Git-теста по таймауту
  («Git command timed out») — воспроизводятся и на чистом HEAD (флаки
  окружения, не связаны с изменениями).

---

## Раунд 2+: новые пункты плана (добавлены 2026-11-09)

Источники: сообщения пользователя в активном чате (сессия
`A0A255E5-…`, проект myCoder) + текущие сообщения в этой сессии.

### Из активного чата

- [ ] **C1. Статус сборки контекста не привязан к chatId.** Строка статуса
  сборки контекста показывается не в том чате, где запущена. Координация с
  параллельным агентом: блокировка билда/правок — кто первый, тот работает,
  второй ждёт; не перезаписывать чужие правки.
  Зацепки: событие сборки должно нести `chatId`; `ContextStageLogLogic`.
- [ ] **C2. Цель (goal) не привязана к чату** в строке состояния и под ней.
  Зацепки: `goals.json`, статус цели в строке состояния.
- [x] **C3. Read-only тулы (list_dir и т.п.) не исполняются в plan mode.**
  Проверено 2026-11-09: `PlanModeToolPolicy.decision` уже возвращает
  `.execute` для всех read-only тулов (default-ветка: read_file/list_dir/
  grep/glob/git_*/todo_read/code_search/read_symbol/web_fetch/browser_fetch/
  skill/task_list), мутации отклоняются. `PlanModeToolPolicyTests`
  подтверждают. Пункт закрыт; если живой прогон покажет иное — вернуть.
- [x] **C4. Двойной набор номера строки** (по скриншоту). Материализатор
  нумерует строки (`N | код`), а вьюер, возможно, добавляет ещё свою нумерацию.
  Сделано (2026-11-10, TDD: `CodeLineNumberingLogicTests`, 8 тестов).
  Причина: `CodeBlockSpoilerView` всегда рисовал свой gutter `1,2,3…`, хотя
  `ContextMaterializer.renderBody` уже встраивает РЕАЛЬНЫЕ номера строк
  файла. Добавлен `CodeLineNumberingLogic.embeddedLineNumbers` (строгая
  проверка: каждая непустая строка `N | ` и номера подряд) и
  `shouldShowGutter` — второй столбец не рисуется. AppKit-рендерер
  (`SelectableMarkdownTextView`) gutter не добавлял, там правок нет.
- [x] **C5. Картинки >1 в сообщении идут в столбик внизу** — нужен коллаж:
  одна большая + остальные сбоку. Зацепки: рендер вложений в `MessageRowView`.
  Сделано (2026-11-10, TDD: `MessageImageCollageLogicTests`, 12 тестов).
  `MessageImageCollageLogic.layout`: 1 → одиночная, 2 → пара, 3+ → большая
  картинка + до трёх миниатюр, лишние сворачиваются в `+N` на последней.
  `MessageDisplayLogic.imagesForDisplay` — единый источник картинок
  (`.image`-части, иначе legacy `attachedImages`), `withoutImageParts`
  убирает их из вертикального текстового потока. `MessageRowView` рисует
  коллаж СЛЕВА от текста пользовательского сообщения; старая горизонтальная
  полоса 80×80 удалена. Регрессии: `MessageDisplayImageTests`,
  `MessageDisplayLogicTests`, `MessageRowLayoutTests` — зелёные.
- [x] **C6. Размер контекста чата не пересчитывается сразу после смены
  модели/параметров** (следующее сообщение уходит со старым размером).
  Сделано (2026-11-10, TDD: `ContextBudgetLogicTests`, 8 тестов).
  Найдены и исправлены три причины:
  1. ручной override контекста/выхода из «Параметров модели»
     (`ModelMetadataStore`) игнорировался: `ModelCapabilityLogic`
     использовал только ответ провайдера. Теперь лимит разрешается через
     `ContextBudgetLogic.effectiveContextLimit` → `ModelMetadataResolver`;
  2. `ContextUsageLogic.usedTokens` суммировал КАЖДЫЙ сохранённый
     `compiledContext`, а каждый пакет уже содержит всю историю — размер
     завышался в разы. Теперь `ContextBudgetLogic.usedTokens` считает
     последний пакет + хвост после него;
  3. правка параметров не будила чат: `ModelMetadataStore.set/clear` шлют
     `.modelMetadataChanged`, `AppState.modelMetadataRevision` публикуется,
     `selectedContextLimit` читает ревизию — бейдж пересчитывается сразу.
  Бейдж, авто-компакция и решение о смене модели используют один источник
  правды. Регрессии: `ContextUsageLogicTests`, `ModelGroupingLogicTests`,
  `ModelMetadataCatalogTests` — зелёные.

### Из текущих сообщений (эта сессия)

- [x] **U1. Чип/спойлер вердикта цели (JSON).** Ответ-вердикт вида
  `{"complete": false, "notDone": [...], "reason": "..."}` показывать
  красивым чипом/спойлером, а не сырым JSON.
  Проверено 2026-11-10: `GoalVerdictCard` + `GoalVerdictPresentationLogic`
  уже встроены (`MessageRowView.swift:271-272`) и покрыты
  `GoalVerdictPresentationLogicTests`. Пункт закрыт.
- [ ] **U2. Плавность прокрутки чата.** При прокрутке вверх/вниз лента
  «докачивается» без показа и резко тормозит. Применить лучшие практики
  мессенджеров (инкрементальная подгрузка, стабильные якоря, отсутствие
  прыжков). Зацепки: `ChatScrollLogic`, `ChatScrollMath`, `ChatPaginationLogic`.
- [ ] **U3. Необработанный tool_call.** `<tool_call>{"name":"read_symbol",
  "args":{"path":"…/WebToolProtocolEmulator.swift","name":"parseToolCalls"}}
  </tool_call>` не обработался. Аудит: все тулы из системного промпта должны
  парситься и исполняться (`WebToolProtocolEmulator.parseToolCalls`, parity-
  тесты `WebToolAllToolsParityTests`).
  Прогресс (раунд 4): парсинг JSON-внутри-`<tool_call>` подтверждён тестами
  (`toolCallXmlWrapperWithJsonParses`, `fencedJsonWithMultilineArgsParses`) —
  восстанавливается через `parseUnfencedJSONToolCalls`; `read_symbol` есть в
  диспетчере (`ProjectWebToolExecutor.run`, case `.readSymbol`) с поддержкой
  `path`+`name`; `PlanModeToolPolicy` пропускает read-only тулы. Осталось:
  живой прогон в приложении, чтобы увидеть фактическую ошибку (вероятно,
  `CodeIndexService.readSymbol` — индекс/символ), и при необходимости —
  улучшить сообщение об ошибке.
- [ ] **U4. Чат прыгает вверх/вниз** при стирании большого текста и замене его
  тулзой; остаётся пустое пространство. При автопрокрутке держать последний
  текст по центру экрана. Зацепки: автопрокрутка (`ChatScrollLogic`).
- [x] **U5. Todo-панель не обновляется.** После «план добавлен» (из буфера
  Clipboard_Screenshot.png) справа план не появляется/не обновляется.
  Зацепки: `todos.json` ↔ `PlanTodoBridge` ↔ UI сайдбара.
  Сделано (2026-11-10, TDD: `TodoPanelSyncLogicTests`, 7 тестов).
  Причина: `AppState.currentSteps` обновлялся только по SSE-событиям, а
  локальный агентский цикл (`ProjectWebToolExecutor.todoWrite` /
  `task_create` / `task_update`) писал `todos.json` и не трогал панель.
  `TodoPanelSyncLogic.updatesChecklist` определяет меняющие инструменты,
  `steps(fromTodoItems:)` превращает сохранённый чеклист в шаги. Оба
  локальных цикла (direct и `AgentToolLoopLogic`) после исполнения читают
  `todos.json` и обновляют `currentSteps` + `showGoal`.
- [x] **U6. Ошибка «invalid JSON — expected a JSON array of todo objects»**
  должна выводить пример корректного форматирования.
  Сделано (раунд 3, коммит `4f0e9d7`): `todoWrite` возвращает пример
  `[{"id":"1","content":"…","status":"pending"}]` в обеих ветках ошибки;
  тесты `todoWriteInvalidJSON`/`todoWriteWrongShapeExample` (TDD: сначала
  красные, после правки зелёные).
- [ ] **U7. Пагинатор (≥23 сообщений)** должен центрировать текущее сообщение
  (или хотя бы не прятать его под нижнюю кнопку). Зацепки: пагинатор,
  `ChatPaginationLogic`, `ChatPaginationLogicTests`.
  Прогресс: в `UserMessageNavigator` уже есть `scrollTo(id, anchor: .center)`
  по `onChange(currentMessageID)`/`onAppear`; подозрение — кейс «текущее —
  последнее сообщение» при 23+ и высоте контейнера 280pt. Нужна живая
  проверка в приложении, затем тест на логику центрирования.

---

## Дисциплина раунда
- Каждый пункт — через TDD: падающий тест → реализация → зелёный прогон.
- Новые файлы ≤600 строк; каждая функция с комментарием
  (вход/выход/что делает/зависимости).
- После раунда: `swift test --no-parallel`, коммит + пуш.
