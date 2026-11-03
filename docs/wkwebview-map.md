# Карта связей `WKWebView` в myCoder (B0.3)

Снимок на 2026-10-29. Цель — зафиксировать все точки, где текущий движок
встроен в приложение, чтобы замена на AntiBrowser (CDP + REST + мини-каст)
покрыла ровно те же поверхности без пропусков.

> Внимание: часть файлов ниже входит в 18 незакоммиченных файлов пользователя
> (помечены «[user]»). Их НЕ трогаем; замена движка — поверх, через
> `BrowserAutomationBridge`.

> Статус (2026-10-30): реализация моста создана —
> `myCoder/Sources/Services/AntiBrowserAutomationBridge.swift` (новый файл),
> использует CDP 9222 для чтения (DOM/куки/скриншоты/навигация) и REST 5390
> для действий (`/act/*`). Ожидает живой интеграции в `WKWebViewBrowserBridge`
> или `WebChatDriver` через протокол `BrowserAutomationBridge`.

## Схема

```
MyCoderApp.swift
  └─ ChatPanelView.swift [user]
       └─ WebProviderBrowserPanelView.swift   — два режима: WKWebView / CDP
            └─ WebBrowserPanel.swift           — пул WKWebView (park / re-parent)
                 └─ WKWebViewBrowserBridge.swift [user] — BrowserAutomationBridge
                      ├─ PermissiveWebNavigationPolicy.swift — WKNavigationDelegate
                      ├─ NetworkInterceptor.swift            — XHR/fetch в WKWebView
                      ├─ WebComposerInputPolicy.swift        — paste-verify
                      ├─ DirectWebAPIClient.swift            — cookies из WKWebView
                      ├─ WebChatDriver.swift [user]          — оркестрация чата
                      ├─ SendSubmissionPolicy.swift          — кнопка отправки
                      └─ FallbackRouter.swift                — fallback-путь чата
└─ MyCoderAPIServer.swift          — HTTP API приложения; строит bridge (стр. 588)
└─ ProjectWebToolExecutor.swift [user] — держит bridge
└─ WebTransportRuntimeLogic.swift  — какой транспорт «настоящий сейчас»
```

## Файлы и роли

| Файл | Роль | Изменён пользователем? |
|---|---|---|
| `myCoder/Sources/App/MyCoderApp.swift` | корень приложения, AppState | да (в списке 18) |
| `myCoder/Sources/Views/ChatPanelView.swift` | панель чата, выбирает режим webProviderBrowserPanelView vs CDP | да |
| `myCoder/Sources/Views/Components/WebProviderBrowserPanelView.swift` | «Оба режима ре-парят ОДИН общий WKWebView — сворачивание паркует» | ? |
| `myCoder/Sources/Views/Components/WebCaptchaSolverView.swift` | показ капчи: `let webView: WKWebView` | ? |
| `myCoder/Sources/Views/Components/WebProvidersSection.swift` | настройки провайдеров; «производственный транспорт — встроенный WKWebView» (стр. 593) | ? |
| `myCoder/Sources/Services/WebBrowserPanel.swift` | пул WKWebView (park / re-parent), 1:1 к вкладке | ? |
| `myCoder/Sources/Services/WKWebViewBrowserBridge.swift` | живая реализация `BrowserAutomationBridge` на WKWebView | да |
| `myCoder/Sources/Services/PermissiveWebNavigationPolicy.swift` | `WKNavigationDelegate`/`WKUIDelegate`, попапы в отдельных NSWindow | ? |
| `myCoder/Sources/Services/NetworkInterceptor.swift` | перехват XHR/fetch внутри WKWebView | ? |
| `myCoder/Sources/Services/WebComposerInputPolicy.swift` | paste-verify протокол ввода | ? |
| `myCoder/Sources/Services/DirectWebAPIClient.swift` | прямой HTTP через URLSession с cookies из WKWebView | ? |
| `myCoder/Sources/Services/WebChatDriver.swift` | оркестрация «набрать → отправить → дождаться ответа» | да |
| `myCoder/Sources/Services/SendSubmissionPolicy.swift` | логика кнопки отправки | ? |
| `myCoder/Sources/Services/FallbackRouter.swift` | fallback-сценарии; ошибки `WKWebViewBridgeError.elementNotFound` | ? |
| `myCoder/Sources/Services/MyCoderAPIServer.swift` | API сервер; строит `WKWebViewBrowserBridge(webView:selectors:)` (стр. 588) | ? |
| `myCoder/Sources/Services/ProjectWebToolExecutor.swift` | исполнение веб-инструментов, держит bridge | да |
| `myCoder/Sources/Services/WebTransportRuntimeLogic.swift` | описывает текущий транспорт («In-app WKWebView») | ? |
| `myCoder/Sources/Services/BrowserAutomationBridge.swift` | **протокол-абстракция** — точка замены движка | ? |

## Что именно заменится

- `WKWebViewBrowserBridge` → реализация `BrowserAutomationBridge` поверх CDP
  (чтение DOM/скриншоты) + REST `/act/*` (человеко-подобный ввод).
- `WebBrowserPanel` (пул вкладок) → менеджер сессий AntiBrowser (профиль +
  вкладки), каждая вкладка = CDP-таргет.
- `PermissiveWebNavigationPolicy` → политика навигации на стороне драйвера
  (allowlist; RSS запрещена по умолчанию).
- `NetworkInterceptor` → CDP `Network` домен (чтение), ввод — только через REST.
- `DirectWebAPIClient` → CDP `Network.getCookies`/`setCookies` + `Runtime` для
  localStorage.

## Что НЕ трогаем

18 незакоммиченных файлов пользователя (см. `git status --porcelain`),
в т.ч. `WebChatDriver.swift`, `ChatPanelView.swift`, `ProjectWebToolExecutor.swift`.
Замена движка реализуется за протоколом `BrowserAutomationBridge`.
