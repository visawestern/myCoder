# Исправление локализации — План

## Текущая проблема
После множества правок переводы для `locAccess*`, `locMode*` были потеряны или сломаны.

## Шаги

1. Проверить текущее состояние ключей в AppLocalization.swift
2. Восстановить переводы для AccessLevel (locAccessAskBefore, locAccessEditAuto, locAccessFull + descriptions)
3. Восстановить переводы для AgentMode (locModeBuild, locModePlan, locModeCompose)
4. Убрать дубликаты и сломанные строки
5. Проверить Settings.swift и InputControls.swift (используют .displayName)
6. Пересобрать и закоммитить
