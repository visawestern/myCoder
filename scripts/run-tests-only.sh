#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# run-tests-only.sh — Запуск тестов ОТДЕЛЬНО от сборки приложения.
#
# Быстрый прогон с фильтром (например, только новые тесты):
#   ./scripts/run-tests-only.sh
#   ./scripts/run-tests-only.sh --filter ModelPickerRowMetadata
#
# ВНИМАНИЕ: SwiftPM компилирует весь модуль тестов даже с --filter —
# это свойство SPM, поэтому первый прогон всё равно долгий; повторные
# прогоны инкрементальные и быстрые.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

swift test --jobs 8 --disable-sandbox "$@"
