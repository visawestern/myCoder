# План интеграции myCoder с AntiBrowser — v2 (2026-11-01)

> Статус: **УТВЕРЖДЁН** (решения пользователя от 2026-11-01):
> - Никакого запасного транспорта: WKWebView полностью вырезается, единственный движок — AntiBrowser.
> - Никаких легаси и заглушек: отсутствующие функции не эмулируются, только реальная реализация.
> - **Вся работа — исключительно через REST API браузера (порт 5390)**: действия `/act/*` (человеко-подобный ввод) + новые страничные ручки `/tabs`, `/page/*`, `/cookies/*` (навигация, чтение DOM/текста, evaluate, скриншоты, куки, localStorage). CDP/WebSocket на клиенте отсутствуют полностью — DevTools-протокол используется только внутри процесса браузера как реализация чтений.

---

## 0. Что показала перепроверка кода (ФАКТЫ)

1. **Протокол `BrowserAutomationBridge`** (`Sources/Services/BrowserAutomationBridge.swift`) — готов и покрывает все операции (navigate, typeText, click, readModelCandidates, screenshot, cookies, setCookies, setLocalStorage, evaluateJS, …). Абстракция менять движок уже есть.
2. **`AntiBrowserAutomationBridge.swift`** создан (395 строк, CDP 9222 + REST 5390, токен из `Local State` → `antibrowser.agent_api.token`), но **нигде не инстанцируется**. Есть пробелы против WK-реализации (см. §3).
3. **Точки создания моста — ровно 8**, все создают `WKWebViewBrowserBridge(webView:selectors:)`:
   - `Views/ChatPanelView.swift:3103` — главный путь отправки (`runWebChatTurn`);
   - `App/MyCoderApp.swift:1957, 1998, 2111` — stopWebGeneration / refreshWebModels / refreshWebEffort;
   - `Services/MyCoderAPIServer.swift:762, 829, 1114` — saveSession / inspect / openLogin;
   - `Views/Components/WebProvidersSection.swift:859` — findModelsBuiltIn (логин-вью).
4. **Жёсткие зависимости от WKWebView**:
   - `WebChatDriver.swift:620–621` напрямую зовёт `WKWebViewBrowserBridge.jsString` (статический хелпер);
   - `FallbackRouter.swift` (строки 469–560) свитчит `WKWebViewBridgeError` (elementNotFound/navigationTimeout).
5. **UI**: `WebProvidersSection.swift:593–609` принудительно ставит `transport = .playwrightMCP` и скрывает любую CDP-опцию; `WebTransportRuntimeLogic.effectiveTransport` всегда возвращает `.playwrightMCP`. Тест `Tests/WebTransportRuntimeLogicTests.swift` закрепляет это поведение.
6. **Пул WKWebView**: `MyCoderApp.webView(for:)` (1761–1826) — единственное место создания web view; `WebBrowserPanel.swift` паркует их в скрытом окне (-2000,0).
7. **Вход/сессии**: `WebSessionManager` хранит cookies+localStorage в `cookies.json` по провайдеру/сессии; `runWebChatTurn` перед ходом делает `bridge.setCookies(payload.cookies)` + `setLocalStorage`; логин сейчас через `WebProviderLoginView` (свой WKWebView) и «Capture Session» (`httpCookieStore.getAllCookies`). Капча решается в `WebCaptchaSolverView` (та же WKWebView).
8. **git**: 18 «пользовательских незакоммиченных» файлов теперь закоммичены (ветка опережает `origin/main` на 18 коммитов). Незакоммичены только `compare-x99-vs-mac.html` и `docs/wkwebview-map.md`. Изменения, тем не менее, делаются **поверх** существующих структур, без переписывания пользовательской логики.

---

## 1. Принципы

- Меняем по минимуму: **фабрика моста** + **новые модули**; логика `WebChatDriver`/`FallbackRouter` не переписывается.
- Вектор замены: WKWebView остаётся как fallback-транспорт, пока AntiBrowser-путь не подтверждён тестами (постепенное переключение, без «одним махом»).
- Ничего не удаляем без функционирующей замены (B12 — только в конце).
- Все изменения коммитим осмысленно; отсутствующие функции не заглушаем.

---

## 2. Часть C — Связь с браузером: запуск, жизненный цикл, готовность

### C1. `EngineLocator.swift` (новый, `Sources/Services/`)
- Поиск сборки AntiBrowser: вложенная `AntiBrowser.app` (если добавлена в bundle), `~/AntiBrowser/out156/Chromium.app`, `/Applications/AntiBrowser.app`, `~/Applications`, путь из UserDefaults.
- Проверка: бинарь существует, версия `156.*` (через `--version` / Info.plist), исполняемый.
- Отдаёт `EngineInfo { appURL, binaryURL, version, verified }` или понятную ошибку «Движок не найден».

### C2. `BrowserProcess.swift` (новый, `Sources/Services/`)
- Запуск: `Antibrowser` с аргументами:
  - `--user-data-dir=<…/Application Support/MyCoder/AntiBrowserProfile>` (отдельный профиль myCoder);
  - `--no-first-run --disable-features=Translate,MediaRouter --restore-last-session=false`;
  - окно за экраном (`--window-position=-2000,0 --window-size=1280,800`); headless — **НЕ** по умолчанию: каст и ручной вход требуют живого рендера (CDP скриншоты работают и в оконном режиме).
- Порты: CDP 9222, REST 5390 по умолчанию; конфигурируемы в настройках myCoder (на случай занятости).
- **Готовность**: поллинг `GET http://127.0.0.1:9222/json/version` до 60 с (ретраи 1 с).
- **Токен**: читается из `Local State` (уже есть в `AntiBrowserAutomationBridge.readToken`).
- **Watchdog**: если CDP/API перестали отвечать — перезапуск процесса (до 2 попыток), затем ошибка пользователю.
- **SingletonLock**: перед запуском проверяем `/json/list`; если там живой профиль с нашим UID — переиспользуем; если порты заняты чужим процессом — честная ошибка с инструкцией (не убиваем чужое).
- **Завершение**: мягко (SIGTERM → подождать 5 с → kill) при выходе из приложения; не гасим чужой браузер.
- Эвикция: один процесс, одна вкладка-таргет на сайт (по провайдеру).

### C3. `EngineStatusCenter` (новый, `Sources/Services/`)
- `@Published var state: EngineState` (lookingFor / launching / ready / error / external — обнаружен внешний браузер).
- Комбинирует EngineLocator + BrowserProcess; источник правды для UI.

---

## 3. Часть B — Доделывание `AntiBrowserAutomationBridge.swift`

Перечень пробелов (проверено по коду) и что делаем:

| # | Метод | Что дополняется |
|---|---|---|
| B1 | `navigate` | После `Page.navigate` ждать `document.readyState == "complete"` (поллинг до 15 с), как в WK; иначе ошибка `.navigationTimeout` |
| B2 | `typeText` | Сначала клик в центр (есть); затем `/act/type`; затем **верификация**: `evalPage` — текст попал в поле? (для contenteditable — innerText; для textarea — value). Если нет — retry (до 2), затем ошибка. Дополнительно: для contenteditable-полей после ввода не нажимать Enter без `pressEnter` |
| B3 | `click` | Сначала `exists`; если кнопка есть, но `disabled` — ошибка «кнопка присутствует, но отключена» (как WK) |
| B4 | `screenshot(selector:)` | Вычислять rect элемента и передавать `clip` в `Page.captureScreenshot`; без селектора — full viewport |
| B5 | `stopGeneration` | Сначала попытка кликнуть стоп-кнопку (селекторы из `WebVendorSelectors.stopButton`), затем Escape |
| B6 | `clickVisibleTextExact` | Реализовать visible-фильтр + normalized exact (как WK: пропуск скрытых, prefix-правило) |
| B7 | `readVisibleModelCandidates` | Скан только «открытых» поверхностей (`data-state="open"`, radix/popper), исключение sidebar |
| B8 | `attachImageToComposer` | Реализовать: через CDP `Runtime.evaluate` — создать `File`/`DataTransfer` и «вставить» в contenteditable (JS-инъекция, без REST) |
| B9 | Ошибки | Маппинг NSError → человеческий текст (домен `AntiBrowserBridge`, коды 1–20), как `WebChatError` |
| B10 | Обработка разрыва | При закрытии WebSocket — все pending-континуации завершать ошибкой «связь с браузером потеряна»; следующий вызов переподключается (уже есть `ensureTarget`, проверяем) |
| B11 | Токен | Если `Local State` пуст (токен ещё не создан) — ждать или запросить через REST `/status`? (не блокируем запуск; API без токена может быть недоступен — тогда ошибка понятная) |

---

## 4. Часть D — Интеграция моста в приложение

### D1. `MainBridgeFactory.swift` (новый, `Sources/Services/`)
- Единая точка создания `BrowserAutomationBridge`:
  - если `EngineStatusCenter` готов → `AntiBrowserAutomationBridge(...)`;
  - иначе → прежний `WKWebViewBrowserBridge(...)` (полный fallback).
- **Все 8 точек создания** переводятся на фабрику (по одной, с сохранением поведения).

### D2. `MyCoderApp.swift`
- Хранить `appState.engineStatus` + ленивый синглтон `AntiBrowserAutomationBridge` (AppState, не локальные инстансы).
- `webView(for:)` остаётся только для fallback-режима; при активном AntiBrowser — не создавать WKWebView для чата (экономия памяти).

### D3. `WebChatDriver.swift:620–621`
- Заменить прямой вызов `WKWebViewBrowserBridge.jsString` на нейтральный хелпер (вынести в `WebJSString.swift` или использовать `bridge.evaluateJS`). Никакой другой правки драйвера.

### D4. `FallbackRouter.swift`
- Заменить свитч по `WKWebViewBridgeError` на общий `Error` + маппинг текста (сохранить формулировки).

### D5. `WebTransportRuntimeLogic.swift`
- `effectiveTransport(for:)`: при активном движке возвращать `.cdpCookies`, иначе `.playwrightMCP`. Обновить `Tests/WebTransportRuntimeLogicTests.swift` под новое поведение (тест «legacy choice cannot claim Chrome attached» — в условиях выключенного движка).

---

## 5. Часть E — UI: выбор движка и статус (настройки myCoder)

### E1. `WebProvidersSection.swift`
- Убрать принудительное `transport = .playwrightMCP`; добавить переключатель «Движок: Встроенный (WKWebView) / AntiBrowser».
- В карточке провайдера — статус движка (зелёный «AntiBrowser готов», жёлтый «запуск…», красный «не найден» + кнопка «Найти»).
- Кнопки «Открыть браузер» (показать окно/каст) и «Войти».

### E2. Новый раздел настроек «Движок»
- Путь к AntiBrowser.app (авто-поиск + ручной выбор), порты CDP/API, кнопка «Проверить подключение» (выполняет `GET /status` и показывает версию/IPFS/API).
- Кнопка «Сбросить профиль браузера» (чистит `AntiBrowserProfile`; осторожно — из UI с подтверждением).

---

## 5b. Часть B2 — Покрытие функций API для четырёх сайтов (аудит 2026-11-01)

Проверено по фактическим вызовам моста в коде myCoder (WebChatDriver,
WebModelDiscovery, FallbackRouter, SmartSend, каст). Все 23 используемые
функции `BrowserAutomationBridge` реализованы в `AntiBrowserAutomationBridge`
исключительно через REST:

| Функция (вызовов) | REST-реализация |
|---|---|
| `wait` (51) | локальный `Task.sleep` |
| `evaluateJS` (29) | POST `/page/evaluate` — **полный доступ к DOM и скриптам сайта** (любой JS: чтение/мутация элементов, обход React-состояния, ожидание промисов) |
| `click` (27) | `evaluate` (видимость/disabled) + POST `/act/click` |
| `exists` (24) | POST `/page/evaluate` (видимость через getClientRects) |
| `currentURL` (22) | POST `/page/state` |
| `waitForSelector` (15) | поллинг `exists` (default протокола) |
| `navigate` (14) | POST `/page/navigate` + ожидание `readyState == complete` |
| `readText` (10) | POST `/page/evaluate` |
| `clickVisibleTextExact` (9) | `evaluate` (normalized exact/prefix, только видимые) + `/act/click` |
| `responseFingerprint` (6) | POST `/page/evaluate` |
| `clickByText` (6) | `evaluate` (exact/contains) + `/act/click` |
| `setCookies` (5) | POST `/cookies/set` |
| `typeText` (4) | `/act/click` + `/act/type` + верификация через `evaluate` |
| `setLocalStorage` (4) | POST `/page/local-storage` |
| `pageText` (4) | POST `/page/text` |
| `cookies` (4) | POST `/cookies/get` |
| `readModelCandidates` (3) | POST `/page/evaluate` (label/fullText/видимость/selectable) |
| `screenshot` (2) | POST `/page/screenshot` (PNG/base64) |
| `readVisibleModelCandidates` (2) | POST `/page/evaluate` (открытые поверхности, исключение sidebar) |
| `stopGeneration` (1) | `evaluate` (стоп-кнопка) + `/act/click` + `/act/key` Escape |
| `scrollBy` (1) | POST `/act/scroll` (dx+dy, колесо тиками) |
| `clickAt` (1) | POST `/act/click` (каст) |
| `attachImageToComposer` (1) | POST `/page/evaluate` (File→DataTransfer→paste) |

Вывод: сайтам нужен именно полный доступ к элементам и скриптам — он обеспечен
`/page/evaluate` (произвольный JS) + человеко-подобными действиями `/act/*`
и страничными ручками (навигация/текст/скриншот/куки/localStorage).

## 6. Часть F — Входы и сессии
### F1. Логин через AntiBrowser (основной путь)
- Кнопка «Войти» в карточке провайдера → `BrowserProcess` поднимает окно браузера (или мини-каст) на `config.chatURL` → пользователь входит руками (обычный браузер, капча решается человеком).
- Куки/сессия живут в профиле AntiBrowser (не в myCoder).
- После входа myCoder проверяет: `WebSessionLogic.inferState` через мост (URL не `/login`, поле ввода есть) → сохраняем «сессия активна».
- **Синхронизация с WebSessionManager**: при успешном входе — `bridge.cookies()` → `WebSessionManager.persist(...)` (чтобы пережить сброс профиля и для fallback-режима).

### F2. Перенос старых сессий (миграция из WKWebView)
- Существующий «Capture Session» (cookies.json) продолжает работать: при старте чата, если в профиле AntiBrowser нет живой сессии, — `bridge.setCookies(payload.cookies)` + `setLocalStorage`, затем `bridge.navigate(chatURL)` и reload (логика уже есть в `runWebChatTurn`, переключается на фабрику автоматически).
- Кнопка «Перенести сессию из встроенного» в карточке провайдера (для явной миграции).

### F3. Капча
- `WebCaptchaSolverView`: вместо WKWebView — показ **мини-каста** браузера (скриншоты) + передача кликов через REST `/act/click`; либо (по выбору пользователя) поднятие окна браузера для ручного решения.
- `WebChatDriver.waitForCaptchaResolution` остаётся без изменений (он работает через bridge и события).

### F4. `MyCoderAPIServer.handleOpenLogin` (1114)
- Переводится на фабрику: при активном движке — открыть окно/каст браузера на URL логина.

---

## 7. Часть G — Мини-каст (B9)

### G1. `ScreencastController.swift` (новый)
- Поток: каждые 300–500 мс `Page.captureScreenshot` (viewport) → `NSImage`; CDP `Page.startScreencast` при наличии (иначе поллинг captureScreenshot).
- Event `screencastFrame` → в UI.

### G2. `BrowserCastView.swift` (новый)
- `NSViewRepresentable`: показывает кадры, передаёт клики/скролл:
  - клик → координаты viewport → REST `/act/click`;
  - скролл → REST `/act/scroll`;
  - (опционально) ввод текста → REST `/act/type` (для капчи/поиска).

### G3. Интеграция
- `WebProviderBrowserPanelView` при активном движке показывает каст вместо WKWebView; `WebBrowserPanel`-пул в этом режиме не используется.
- `ChatPanelView` minimap/expanded — поверх каста.

---

## 8. Часть H — Тесты

| Блок | Что | Как |
|---|---|---|
| H1 | Юнит-тесты `AntiBrowserAutomationBridge` | Мок CDP/REST (URLProtocol или инъекция транспорта): navigation wait, typeText verify, screenshot clip, ошибки |
| H2 | Юнит-тесты `EngineLocator`/`BrowserProcess` | Фейковый движок в tmp, поллинг готовности, singleton-проверка |
| H3 | Интеграция на локальной странице | `python3 -m http.server` + тестовая страница: navigate/type/click/read/снимок через настоящий AntiBrowser |
| H4 | Живые сайты | Расширить `scripts/verify-ai-sites.sh`-подход на Swift-драйвер: kimi/chatgpt/claude/gemini — вход (где есть), отправка, чтение ответа |
| H5 | Регрессия WK-пути | Существующие тесты и ручные сценарии остаются зелёными (fallback) |
| H6 | E2E мини-каста | Открыть каст, кликнуть по координате, убедиться что клик дошёл (событие на странице) |

---

## 9. Порядок работ

1. ✅ **C1–C3** (EngineLocator + BrowserProcess + EngineStatusCenter) — фундамент связи.
2. ✅ **B1–B11** (дошлифовка AntiBrowserAutomationBridge) + **H1/H2**.
3. ✅ **D1–D5** (фабрика моста, перевод 8 точек, jsString, FallbackRouter, WebTransportRuntimeLogic + тест H5).
4. ✅ **E1–E2** (UI выбора движка и статус).
5. ✅ **F1–F4** (входы: логин в AntiBrowser, миграция сессий, капча через каст).
6. ✅ **G1–G3** (мини-каст).
7. 🔵 **H3/H4/H6** (интеграционные и живые тесты): H3 ✅ (PageApi E2E 10/10), H4 ✅ (AI-сайты 6/6/6/3 до рефакторинга), H6 ⬜ (каст — GUI, нужен пользователь).
8. ✅ **B12-финал** (удаление WKWebView-пула) — выполнено по решению пользователя «без легаси и заглушек»: WK функционально вырезан, остались нейтральные `#if canImport(WebKit)` обёртки.

## 10. Что НЕ входит в этот этап

- A14 (подпись/нотаризация браузера) — отдельно, нужны Apple Developer credentials.
- A15 (апдейтер браузера) — отдельное решение.
- Полная визуальная проверка GUI (каст/логин/статус движка) — требует пользователя.
- Изменения `compare-x99-vs-mac.html`, `docs/wkwebview-map.md` (пользовательские untracked-файлы) — не трогаем.

## 10b. Финальная верификация (2026-11-02)

- ✅ `swift test`: 3202 теста; падения — только флейки под нагрузкой (`approvalBoxDeliversAnswerAcrossThreads`, `ChatMarkdownCacheTests.cachedBuild…`, `ProviderAutoDetectorTests` deadline-пробы), все проходят в изоляции; к интеграции отношения не имеют.
- ✅ Регрессия REST API на финальном бинаре: `verify_final.sh` 21/21 + `verify_pageapi.sh` 10/10.
- ✅ Полный хелп на неверной команде: `POST /nonsense` → 23 эндпоинта в `hint`.
- ✅ Сборка `.app` (`build-app.sh --skip-tests`): **v2.119.15 (build 132)**, подпись верифицирована, ресурсы на месте.
- ⚠️ Осталось для пользователя: визуальная проверка движок-карточки, каста, логина через каст.
- Подробности — в `docs/checklist-browser-status.md`.

## 11. Риски и открытые вопросы

1. **Порты** 9222/5390 могут быть заняты тестовым браузером → конфигурируемые порты + SingletonLock (решение: C2).
2. **Capcha**: у headless нет окон, у оконного режима есть — поэтому по умолчанию оконный режим за экраном (решение: C2).
3. **Капча/логин вбраузере vs cookies.json**: если обе сессии существуют — приоритет живой сессии в профиле AntiBrowser; перенос — явной кнопкой (F2).
4. **Нагрузка на машину**: один браузер-процесс на всё приложение (не на каждый чат), вкладки-таргеты — по сайту.
5. Вопрос пользователю: **оставлять ли WKWebView как fallback** после успешной интеграции (или сразу резать после зелёных тестов)?
6. Вопрос пользователю: **окно браузера при входе** — отдельное видимое окно или мини-каст в приложении (по умолчанию: мини-каст + кнопка «открыть окно»)?
