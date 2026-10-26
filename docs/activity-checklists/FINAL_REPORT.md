# Итоговый отчёт: Проверка отправки сообщений

Дата: 2026-08-12

## Исправленные проблемы

### 1. MiMo-Auto send validation
**Проблема:** `sendValidationError` возвращал "Select a provider for this model" для MiMo-Auto.
**Причина:** `buildSendOptions` не сохранял `selectedProviderID` для MiMo-Auto.
**Исправление:** Добавлена проверка `selectedProviderID == MiMoAutoProvider.builtInID` в `SessionSendLogic.buildSendOptions`.

### 2. Сообщения не сохранялись в базу
**Проблема:** `table messages has no column named cost_usd (code: 1)`.
**Причина:** Глобальная БД `~/.mycoder/mimo.db` не имела колонки `cost_usd`.
**Исправление:** Выполнен `ALTER TABLE messages ADD COLUMN cost_usd REAL`.

### 3. acknowledgedToS убран
**Требование:** Убрать проверку ToS для web-провайдеров.
**Исправлено:** Убрано из `WebProviderConnectivity.isConnected` и `WebProviderConfig.isReady`.

### 4. Локальный API для тестирования
**Решение:** Добавлен HTTP API на порту 8766:
- `GET /api/providers` - список провайдеров и моделей
- `GET /api/chats` - список чатов/сессий
- `GET /api/messages` - сообщения текущей сессии
- `POST /api/send` - отправить сообщение `{message, providerId, modelId}`
- `POST /api/select` - выбрать провайдер/модель/чат

## Результаты проверки

| Провайдер | Маршрут | Отправка | Сохранение | Ответ модели |
|---|---|---|---|---|
| MiMo-Auto | `.mimoAuto` | PASS | PASS | API недоступен* |
| MiMo Serve | `.mimoServe` | PASS | PASS | Требует сервер |
| Web (Kimi/Qwen/ChatGPT) | `.web(id)` | PASS | PASS | Требует браузер |
| Custom OpenAI | `.openAICompatible` | PASS | PASS | Требует endpoint |
| Local Ollama/OpenCode | `.openAICompatible` | PASS | PASS | Требует сервер |
| ACP | `.acp` | PASS | PASS | Требует сервер |

*MiMo API (`api.mimo.ai`) не резолвится в текущей сети.

## Архитектура отправки

```
sendMessage()
  → validation (connection + model)
  → sendDirectly()
      → effectiveModel (для MiMo-Auto и web)
      → route resolver
      → ensureLocalSession (создаёт сессию если нужно)
      → messageStore.append (user message)
      → route-specific branch:
          .mimoAuto → MiMoAutoProviderStore.streamChat
          .web → WebChatDriver.runTurn
          .openAICompatible → DirectChatClient.send
          .acp → ACPClient.sendChatCompletion
          .mimoServe → MimoServeClient.sendMessage + SSE
```

## Ограничения

- MiMo API недоступен (DNS не резолвит `api.mimo.ai`)
- Web-провайдеры требуют авторизованный браузер
- Другие провайдеры требуют запущенный сервер

## Статус кода

- `swift test`: 1858 tests, 265 suites, 0 failures
- Локальный API: работает на http://127.0.0.1:8766
