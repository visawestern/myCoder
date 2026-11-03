# AntiBrowser × myCoder: проверка 2026-11-03

Это текущий журнал проверки, а не перенос прежних PASS. До завершения новой
сборки приложения и живого прогона пункты B1/B1a/B2 не считаются закрытыми.

## Исходное состояние

- Процессы myCoder, Chromium и сборщик ninja отсутствуют; порты 8766 и 5390
  не слушают. Поэтому закрытый 5390 сейчас **не доказывает** ленивый старт
  после запуска приложения.
- `/tmp/build_engine25.log` заканчивается на `[3/36] SOLINK libchrome_dll.dylib`.
  В `.ninja_log` есть завершённая запись линковки этой библиотеки, но нет
  подтверждения завершения всей сборки/упаковки движка. engine25 — **не подтверждён**.
- `libchrome_dll.dylib` существует и определяется как Mach-O x86_64; это
  подтверждение наличия артефакта, а не поведения окна.
- Последний сохранённый `/tmp/build_app15.log` заканчивается успешной сборкой
  v2.119.15 (132). Это старая сборка до текущих изменений контекста.
- Исходники найдены через `out156/build.ninja`:
  `/Users/apple/anti-browser-2579e801-68230474-f6946f22-158382b1/chromium/src`.
  Проверено по исходнику: `BrowserNativeWidgetMac::ShouldSaveWindowPlacement`
  возвращает false (`browser_native_widget_mac.mm:899`), Activate использует
  kShowInactive (`:380`), обе коррекции окна используют -4000 (`:810`, `:817`),
  исходные bounds также -4000 (`browser_window_state.cc:176`).
  `antibrowser.no_startup_window` зарегистрирован в antibrowser_prefs.cc и
  читается в `IsSilentLaunchEnabled` (startup_browser_creator.cc:364).
- Запущено завершение существующей сборки (только сборка, не процесс движка):
  `ninja -C /Users/apple/AntiBrowser/out156 chrome`;
  журнал `/tmp/mycoder-engine25-complete.log`. Сборка остановлена до первого
  шага компиляции/линковки (exit 130): ninja сообщил
  `build log version is too old; starting over`. После этого
  `out156/.ninja_log` отсутствует. Это изменение состояния сборочного дерева
  произошло при попытке продолжить сборку; его влияние не скрывается.
  `.ninja_deps` (119545600 байт) и существующие бинарные артефакты на месте.
- `out156/.ninja_log.old`, `.ninja_log.recompact` и backup в `~/AntiBrowser`
  или `/tmp` не найдены. Журналы в `out`/`out_scratch` относятся к другим
  сборочным деревьям и не использовались для подмены.
- Диагностический `ninja -n -j2 chrome` завершился exit 0 и показал
  **56 476** действий. Это dry-run, а не успешная сборка движка; дальнейшая
  реальная пересборка не запускалась. Потеря/непризнание журнала означает,
  что последующая сборка out156 может потребовать большой повторной работы.
  engine25 по-прежнему UNVERIFIED; профиль и процесс движка не запускались.

## Проверено по текущему коду

| Пункт | Наблюдение | Граница проверки |
|---|---|---|
| B1a | `MyCoderApp.onAppear` не запускает EngineStatusCenter | Нет живого B0 до новой сборки |
| B1a | `AntiBrowserAutomationBridge.post` вызывает `ensureEngineStartedIfNeeded` | Живой запуск ещё не выполнен |
| B1a | AntiBrowserTabManager даёт профиль мосту до конфигурации | 6 тестов присутствуют; результат текущего прогона ниже |
| REST | Мост вызывает REST; CDP не используется в Swift-мосте | Движок не запускался |
| Профиль | BrowserProcess.Config.defaultProfileDir соответствует `~/Library/Application Support/MyCoder/AntiBrowserProfile` | Сохранение cookie через рестарт не повторялось |
| B2 | Парсер, рендер и диспетчер browser_fetch реализованы; 22 теста присутствуют | Живой текст + screenshot + click ещё не выполнен |

## Найденная причина лишнего запуска

`EngineLocator.verify` обещал проверку без запуска, но вызывал исполняемый
файл Chromium с `--version`. Это отдельный процесс до `BrowserProcess`,
без единственного разрешённого аргумента `--user-data-dir`.
Исправление проверяется тестом с безвредным тестовым исполняемым файлом:
обнаружение должно читать версию из Info.plist и не запускать файл.

TDD: `/tmp/mycoder-engine-locator-red.log` — **RED подтверждён**: 3 теста,
2 упали (4 issues). Исполняемый fixture создавал marker, а версия бралась
из его stdout вместо Info.plist. После этого удалён запуск `--version`.
`EngineLocator.verify` теперь читает только исполняемость пути и Info.plist.

`/tmp/mycoder-engine-locator-green.log` — прогон не дошёл до исполнения
тестов: общий test target содержит одновременно добавленные RED-тесты
TurnDelivery/InternalTaskPlanner/ImpactAnalyzer. Их отсутствующие API дали
ожидаемые ошибки компиляции; GREEN локатора остаётся **PENDING** до общего
прогона root. Браузер/движок ни разу не запускались в ходе проверки.

## Открытые несоответствия требований

1. Буквальное «окно только по кнопке Войти» расходится с текущим B1a:
   `ensureTab` создаёт вкладку по первому запросу веб-чата/browser_fetch.
   Проверка окна должна различать запуск движка без вкладки и первый запрос
   вкладки. В этой проверке поведение не менялось.
2. Найденный второй флаг `engine.headless` устранён через TDD:
   `BrowserProcessArgumentsTests` сначала дал RED (нет `launchArguments`;
   `/tmp/mycoder-final-contract-red.log`). После этого убраны поле headless,
   чтение устаревшей настройки и добавление `--headless`. Конфигурация выдаёт
   единственный `--user-data-dir`, включая пути с пробелами. GREEN — в общем
   прогоне root; значения пользовательских настроек и профиль не менялись.
3. Скрипт `/tmp/window_check.swift` проверяет только основной экран и
   `optionOnScreenOnly`; его PASS недостаточен для строгой проверки всех
   дисплеев, существования скрытого окна и отсутствия захвата фокуса.
4. `/tmp/verify_login_pages.sh` работает прямо через REST5390, но не запускает
   движок. Его можно выполнять после запуска через myCoder; прямые внешние
   запуски Chromium не использовались.

## Следующий живой прогон

После полного selftest PASS и сборки `.app`: запустить только myCoder,
проверить закрытый 5390 до действий, вызвать «Войти» через приложение/API8766,
проверить окно и фокус, аргументы, страницы входа 4 провайдеров, затем
browser_fetch (текст + screenshot + click). До этого эти результаты — NOT RUN.

## Какой артефакт загрузит текущая Chromium.app

Read-only `otool`/`stat` проверка:

- В app лежит `Chromium Framework` размером 4192 Б (30 октября), а
  `out156/libchrome_dll.dylib` — 161858392 Б (3 ноября 18:37:58, время host).
  Это разные файлы/inode: framework — штатный reexport stub component-build.
- `otool -L` framework показывает `@rpath/libchrome_dll.dylib (reexport)`.
  Его первый LC_RPATH `@loader_path/../../../../../..` разрешается ровно в
  `/Users/apple/AntiBrowser/out156`; найденный файл `samefile` с just-linked
  `libchrome_dll.dylib`. Остальные два rpath не содержат копии этой библиотеки.
- Главный executable ссылается на framework через `../Frameworks`.
  `engine.path` в preferences `com.mycoder.app` не задан, вложенной
  `AntiBrowser.app` в ресурсах myCoder нет: локатор выберет out156.
- `llvm-objdump` точного символа
  `__ZNK22BrowserNativeWidgetMac25ShouldSaveWindowPlacementEv` в этой dylib
  показывает `xorl %eax, %eax; retq` — возврат false уже находится в бинаре.
  Соответствующие объекты исходников датированы 18:37:26 и 18:37:48.

Вывод: для **этой component-app в out156** копировать новую 161 МБ библиотеку
поверх 4192 Б framework не требуется. Она будет найдена по rpath при запуске
через myCoder. Безопасная следующая проверка — такой запуск и проверка
реально загруженного пути/окна. Это не означает PASS полной сборки engine25
или проверки поведения окна; запуск в ходе этого metadata-анализа не выполнялся.

## Opt-in живой browser_fetch

Добавлен `BrowserFetchLiveIntegrationTests.swift`: один тест выключен по
умолчанию через `.enabled(if:)`. Для запуска нужны `MYCODER_LIVE_BROWSER=1`,
`MYCODER_BROWSER_FIXTURE_URL` и заранее поднятый **через myCoder** REST5390.
Тест не запускает движок (`bridge.engineBootstrap=nil`), читает/выполняет JS,
кликает, проверяет PNG реального скриншота и закрывает только свою вкладку.
Результат — NOT RUN до отдельного запуска root после appbuild.

## Внутренний API для browser_fetch

Добавлено действие `browser.fetch` в `/api/action` и каталог `/api/actions`.
Оно использует настоящий `ProjectWebToolExecutor` и app-owned мост
AntiBrowserTabManager; движок может лениво запуститься только из myCoder.
Параметры `url` (обязательный http/https), `selector`, `script`, `click`,
`screenshot`, `limit` проверяются до получения моста. Вложенные object/array
и нецелые числовые аргументы отклоняются; нормализация и планировщик общие
с настоящим инструментом.

Запрос:

```json
{"action":"browser.fetch","params":{"url":"http://127.0.0.1:8000/fixture.html","selector":"#payload","screenshot":true,"limit":2000}}
```

`/api/action` сохраняет свой общий envelope: внешний `ok` подтверждает
выполнение action router, `result.ok` — семантический успех browser_fetch.
Проверять нужно оба. `result.output` хранит исходный ответ/ошибку, включая
маркер PNG; `result.screenshot`/`screenshotBytes` описывают полученный PNG.

TDD: `/tmp/mycoder-browser-api-red.log` зафиксировал отсутствие helper до
реализации; `/tmp/mycoder-browser-api-green.log` — **14/14 PASS**, 3 сьюта
(BrowserFetchAPILogic, ToolInstructionGuide, AppActionRouter). Среди проверок —
неизменность состояния движка/мостов при невалидном API-запросе. Живой вызов
через собранную `.app` на этом этапе ещё NOT RUN.

## Живой API-прогон 2026-11-04: B0 PASS, B1 FAIL

После нового selftest/build, выполненных root, myCoder запущен через `open`.
Действия этой проверки выполнялись только через внутренний API8766;
Chromium отдельно не запускался.

- B0 **PASS**: порт5390 закрыт после запуска myCoder; невалидный
  `browser.fetch` с file:// URL отклонён и порт остаётся закрыт.
- `/api/providers` показывает только один настроенный web-провайдер Kimi.
  Qwen/ChatGPT/Claude в этой конфигурации отсутствуют; 4/4 заявлять нельзя.
- Первый `/api/open-login` Kimi **успешен**, движок лениво стартовал:
  ChromiumPID39805 — дочерний процесс myCoderPID39473; единственная опция
  командной строки — `--user-data-dir` с требуемым постоянным профилем.
- B1 **FAIL**: в зарезервированном интервале без UI-действий root фронтмост
  изменился с `com.workbuddy.workbuddy-ai` на `org.chromium.Chromium`.
  Главное окно1280×800 находится в x=-1240,y=30 и onScreen=true:
  видна полоса шириной40px. Настройки приложения/выбранный чат не изменились.
- Проба перечисляет9 окон этого PID; остальные включают скрытые вспомогательные
  окна. Главный дефект подтверждён одним реально видимым окном, поэтому
  результат не зависит от трактовки границ скрытых служебных окон.
- `vmmap` подтверждает загрузку именно новой
  `/Users/apple/AntiBrowser/out156/libchrome_dll.dylib`.
  LocalState содержит no_startup_window=true, Preferences содержит
  window_placement.left=-4000. Следовательно, исправление
  ShouldSaveWindowPlacement=false и заданная геометрия сами по себе
  не устранили наблюдаемое поведение. Дальнейшая причина требует исправления
  движка и повторного живого теста.

Артефакты: `/tmp/mycoder-browser-api-evidence/baseline-*.json`,
`first-login-*.json`, `runtime-library-mappings.txt`.
После этого FAIL дальнейшие providers/fixture/search в данном этапе не
запускались; root уведомлён, операции заморожены.
