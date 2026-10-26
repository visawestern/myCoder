# myCoder — Сводный отчёт проекта

Дата: 2026-08-22

## Результат текущего цикла

- Все активити покрыты отдельными Markdown-чеклистами в `docs/activity-checklists/`.
- Каждый пункт содержит действие, триггер, ожидаемое поведение, качество и источник кода.
- Канонический реестр user stories: `docs/FEATURE_SPREADSHEET.csv`.
- Полный тест: `2249 tests / 355 suites` — все зелёные.
- Сборка: `swift build — green`.
- Round 30: приложение запущено и проверено ЖИВО через встроенный API (порт 8766) на реальных веб-провайдерах.
- Сводка spreadsheet: `172 PASS`, `11 PARTIAL`, `8 MISSING`, `5 FUTURE`.

## Активити

1. `01-sidebar.md` — workspaces, задачи, архив, уведомления, поиск, настройки.
2. `02-chat-panel.md` — ввод, отправка, streaming, attachments, Markdown, tool calls, Plan-вопросы.
3. `03-right-panel.md` — Git, ветки, commit, push/pull, прогресс и Premium-flow.
4. `04-bottom-panel.md` — Terminal и Git tabs, команды, остановка, история, изменения.
5. `05-settings.md` — все 10 видимых вкладок Settings.
6. `06-topbar-taskheader-statusbar-newproject.md` — top bar, task header, status bar, project sheet.
7. `07-app-shell-modals-and-menu.md` — ContentView, macOS commands, overlays, restore and routing.

## Исправлено в текущем цикле

- E13: read-only/system path fallback в `~/.mycoder/projects/<stable-hash>/project.db`.
- E21: WAL journaling и честный размер базы с учётом `-wal`/`-shm`.
- E30: удалён скрытый лимит 100 проектов, явные лимиты сохранены.
- E04: on-disk SQLite header validation и read-only integrity probe без schema mutation.
- Test isolation: scoped project eviction вместо глобального `evictAll()`.
- UX: объяснение disabled Plan-agent и точное сообщение о пропущенном push.
- Rebrand: stale user-facing MiMo strings обновлены на myCoder.
- **P1**: `DatabaseBridge.saveMessagePart` — `.stepStart` теперь использует `insert` closure (данные пишутся в project DB, а не в legacy global).
- **P3**: `Message.reasoningDuration` — добавлен `reasoningEndedAt`, значение замораживается после завершения reasoning.
- **P4**: `ProjectWebToolExecutor.todoRead/todoWrite` — реализована полноценная persistence в `<project>/.mycoder/todos.json` (было: stub-заглушки).

## Раунд 28 (2026-08-20)

- **P1 (HIGH)**: `todoRead` теперь обрабатывает оба формата JSON (bare array и `{"todos": [...]}` wrapper) — предотвращает тихую потерю данных.
- **P2 (MED)**: `SSEClient.connect()` использует `[weak self]` для предотвращения retain cycle.
- **P4 (LOW)**: `SSEClient.sharedSession` timeouts изменены с `Int.max` (~68 лет) на 300s/600s.
- **P5 (LOW)**: `grep()` теперь предупреждает об обрезке результатов при 500+ файлах.
- **P6 (DOC)**: `FEATURE_REGISTRY.md` заголовок обновлён на "myCoder".
- **P7 (MED)**: `E09E10ToolUndoHistoryTests` исправлен с `accessLevel: .fullAccess`.

## Раунд 29 (2026-08-21)

- **R1 (HIGH, security)**: git-инструменты (`git_commit/checkout/push/pull/log`) интерполировали модельные `message`/`branch`/`remote`/`limit` в `/bin/zsh -c` без экранирования — инъекция произвольного шелла под видом одобренной операции. Фикс: `shellQuoted`/`sanitizedNumber`, извлечённые билдеры команд + интеграционный тест на реальном git-репо (side-effect файл не создаётся).
- **R2 (MED)**: grep обрезался ровно на 100-м совпадении без предупреждения (ранний return обходил логику Round 28). Фикс: single-exit с флагами + предупреждение о лимите совпадений.
- **R3 (MED)**: glob сверял паттерн только с именем файла — любой паттерн с `/` (`src/*.swift`, `**/*.swift`) всегда возвращал «(no matches)». Фикс: полноценный glob→regex (`*` не пересекает `/`, `**` — да), матч по пути от корня, сортировка, лимит 500 + предупреждение; попутно исправлен скрытый symlink-mismatch (`/var` vs `/private/var`).
- **R4 (HIGH)**: `/api/send` отвечал устаревшими chatId/providerId/modelId — ответ строился из значений, снятых ДО асинхронных мутаций main-потока (для нового чата возвращался пустой/чужой id). Фикс: `resolveSendTargets` (@MainActor) возвращает состояние после мутаций; semaphore-паттерн как в остальных хендлерах; при таймауте 30s — честная ошибка вместо устаревших данных.
- **R5 (LOW)**: фикс Round 28 P4 выставил SSE-таймауты в `sharedSession`, но `connect()` продолжал использовать `URLSession.shared` — правка не имела эффекта. Теперь используется настроенная сессия.
- **Quality pass**: все фиксы раунда перепроверены вручную по цепочкам. Найдены и закрыты 2 пробела: grep скрывал усечение при нуле совпадений на >500 файлах; инъекционная защита доказана end-to-end и для `git_checkout` (не только `git_commit`). Прочитанные-не-на-main @Published состояния в GET-хендлерах зафиксированы как осознанный trade-off (блокировка GET на MainActor рискует зависаниями API; класс SIGSEGV — write-driven).

## Раунд 30 (2026-08-22) — живой пайплайн через встроенный API

Приложение собрано, запущено и управляется через собственный API (127.0.0.1:8766): выбор провайдера → встроенный браузер → отправка реального сообщения в qwen.ai → захват ответа. Все находки верифицированы на РАБОТАЮЩЕМ приложении и логах.

- **W1 (HIGH)**: у WKWebView не было UIDelegate — `window.open`/`target=_blank` (передача kimi.com→kimi.ai) молча терялись, JS-диалоги могли вешать страницу. Фикс: `PermissiveWebNavigationPolicy` (полный allow навигации, попапы in-place, авто-ответ диалогов) на пуле браузеров и окне логина. Живое доказательство: window.open ведёт ту же вьюху, alert мгновенный.
- **W2 (HIGH)**: глобальная БД вставляла сообщения plain INSERT — каждый стрим-апдейт падал по UNIQUE constraint, в истории оставались пустые пузыри ассистента. Фикс: replace-on-conflict как в проектной БД (красный→зелёный + живое подтверждение).
- **W3 (HIGH)**: FallbackRouter объявлял успех отправки после одного click() без проверки. Фикс: `SendSubmissionPolicy` — верификация по появлению chat-id в URL с ограниченными ретраями; фейковый успех устранён (в живом логе: «submission verified via URL change»).
- **W4 (MED)**: селектор кнопки отправки Qwen бил в DIV-обёртку-заглушку; реальный триггер — внутренний `<button class="send-button">` (доказано ручным DOM-экспериментом, получен настоящий ответ модели). Каталог исправлен.
- **W5 (MED)**: discovery сетевых маршрутов предлагал телеметрию (`users/status`) с ОТНОСИТЕЛЬНЫМ URL → `-1002 unsupported URL`. Введены фильтры мусорных путей и абсолютности URL.
- **W6 (MED)**: биндинг remote-чата кликал «New Chat» до проверки уже открытого чата, уничтожая только что отправленную переписку. Теперь открытый чат переиспользуется.

Честный остаток (не замаскирован): ложный негатив инжекции модели Qwen при живых моделях в DOM (дрейф селекторов дропдауна) и следующее за ним обновление каталога, уводящее со страницы до захвата финального ответа; Kimi честно ждёт ручного логина. Детали: `docs/DEVILS_ADVOCATE_ROUND_30_2026-08-22.md`.

Честный остаток Round 30 (дрейф DOM qwen.ai) закрыт в **Round 30b** подбором селекторов вживую: префиксный матч для пунктов «имя+описание», актуальный триггер/опции усилия, англ. лейблы Auto/Think/Fast + легаси-фолбэки, ожидание стабильности URL и ретраи инжекции, pre-send fingerprint для захвата ответа. **Полный пайплайн через API работает end-to-end**: отправка → доставка верифицирована → модель Qwen3.7-Plus+effort применены → ответ захвачен («2026» на вопрос о годе) → remote chat привязан → всё персистится. Детали: `docs/DEVILS_ADVOCATE_ROUND_30_2026-08-22.md`.

**Round 30c**: по репорту пользователя возвращены/починены UI-цепочки: плитка вендора теперь добавляет ВТОРОЙ аккаунт (клон настроек, новый id, без копирования кукисов; подпись «+ Аккаунт» на 10 языках) вместо мёртвой кнопки; детект моделей/усилия запускается автоматически при открытии окна логина — до захвата сессии и кукисов.

## Остаток по концепту

Оставшиеся `PARTIAL`, `MISSING` и `FUTURE` статусы не скрыты и перечислены в
`FEATURE_SPREADSHEET.csv`. Основные следующие продуктовые блоки: registry/settings export,
chunked delete, skill updates/dependencies, persistent file indexing, usage cost aggregation,
storage localization, interactive captcha bridge и опасные команды.

Интерактивные native macOS проверки Finder, Keychain, drag/resize и реальные remote/GitHub
сценарии отмечены как условные: в текущем окружении нет живого UI-сеанса. Они не выдаются за
кликнутые вручную; логика и unit-тесты проверены отдельно.

## Критерий качества

Нет намеренных заглушек в закрытых user stories. Неполные функции остаются явно отмеченными
`PARTIAL`/`MISSING`/`FUTURE`, а не маскируются статусом PASS. Каждый следующий раунд должен:

```text
/goal → code-based user stories → canonical spreadsheet → real/error testing
→ fix logistics and UX → repeat every behavior → devil's-advocate review
```

---

## Дельта-аудит 2026-09-06 (коммиты 6062877..HEAD + фиксы сессии)

**Контекст:** аудит от 2026-09-04 не покрывал 14 пост-аудитных коммитов
(~820 строк: agentic tool loop, auto-context, goal progress, history paging,
tool-call JSON). Проведён дельта-аудит по циклу: обнаружение → фиксация →
user story → ожидаемое поведение → тест → первопричина → фикс → повторный
тест → регрессия.

**Новые activity-чеклисты:** 30-agentic-tool-loop, 31-project-auto-context,
32-header-goal-progress, 33-history-tail-paging (docs/audit/).

**Исправлено в этой сессии (все — первопричинно, без обходных путей):**

1. **ARCH-03/08 (HIGH)** — data race на `lastAccessedAt` + мёртвая
   DispatchQueue в ProjectDatabaseManager. NSLock-сериализация; очередь
   удалена. Регрессионный тест: 50 конкурентных открытий пула.
2. **ARCH-04 (HIGH)** — провайдер с валидным ключом блокировался/уходил без
   Authorization до перезапуска после Keychain-миграции (2 независимых
   сайта: readiness-валидация и route-resolver). Ключ восстанавливается
   in-memory; route резолвится через getSecureAPIKey(). Регрессионный тест.
3. **ARCH-05 (MEDIUM)** — SQL-интерполяция в addColumnIfMissing заменена
   allowlist'ом owned-идентификаторов + типизированной ошибкой.
4. **ARCH-06 (MEDIUM)** — symlink path traversal: realpath + лексическая
   резолюция `..`/`.` + walk-up по longest-existing-ancestor. ВАЖНО: первая
   версия фикса вводила бесконечный цикл (URL.deletingLastPathComponent —
   no-op на trailing `..`) и неверный lexical guard; поймано ТОЛЬКО полным
   регрессионным прогоном (hang на 200% CPU). 10 регрессионных кейсов.
5. **ARCH-09 (LOW)** — дублированные конвертеры parts → общий
   convertPartFields.
6. **BUG-30-01 (MEDIUM)** — tool-преамбула auto-free без projectRoot/git
   контекста (модель не могла резолвить относительные пути инструментов).

**Финальная регрессия:** 2298 tests / 359 suites — 0 failures, GREEN.

**SDLC-вывод (подтверждён эмпирически):** компиляция и targeted-тесты
недостаточны — BUG-30-02 прошёл все быстрые проверки и был поймат только
полным прогоном. Контур качества обязан замыкаться на независимую
валидацию (полный прогон + ручные edge-case проверки), а не на скорость
генерации фикса. Ускорение Code без переноса контроля в Review+Tests
перемещает узкое место дальше по потоку.

**Канонический spreadsheet:** docs/FEATURE_SPREADSHEET.csv — 286 записей
(все user stories, включая дельту); docs/audit/FEATURE_SPREADSHEET_AUDIT.csv
— 285 записей с полным трекингом severity/bugs/fix/test.

**Остаточные внешние ограничения (зафиксированы явно, не скрыты):**
- ARCH-01 (god-object AppState) — требует структурного разложения; является
  предусловием для полного устранения ARCH-02. Инкрементальные патчи без
  разложения = маскирование симптомов; записан как долг с моделью замены.
- ARCH-07 (39 `try?`) — требует дизайна канала ошибок UX (~45 сайтов).
- Native-macOS-only проверки (Keychain live, WKWebView runtime, FSEvents) —
  вне достижимости текущего окружения; помечены UNVERIFIED, не PASS.
