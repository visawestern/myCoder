# Web Provider Model Detection — Test Results

> Date: 2026-08-10
> Tested via Playwright against live sites

## Summary

| Provider | Status | Models | Model Button Selector | Model Item Selector |
|----------|--------|--------|----------------------|---------------------|
| Kimi | ✅ Works | 3 | `div.current-model` | `div.model-item span.name` |
| Qwen | ✅ Works | 3 | `[class*="model-selector-text"]` | `[class*="model-item-name"]` |
| ChatGPT | ❌ Needs login | — | `button[data-testid="model-switcher-dropdown-button"]` | — |

## Kimi (Moonshot AI)

### Selectors
- **Model button:** `div.current-model`
- **Dropdown items:** `div.model-item`
- **Model name:** `span.name`
- **Effort button:** `div.effort-item`

### Models Found
1. Быстрый — Быстрый чат, мгновенные ответы
2. K3 — Универсальная флагманская модель для чатов и задач Agent
3. K3 Swarm — Масштабный поиск, пакетная обработка

### Flow
1. Navigate to `https://kimi.moonshot.cn`
2. Click "Новый чат" (text match)
3. Wait for `div.current-model` to appear
4. Click `div.current-model` to open dropdown
5. Wait for `div.model-item`
6. Read `span.name` from each item

## Qwen (Alibaba)

### Selectors
- **Model button:** `[class*="model-selector-text"]` or `.index-module__model-selector-text___XvWe0`
- **Dropdown items:** `[class*="model-item-name"]`
- **New chat button:** `button` with text "Начать"

### Models Found
1. Qwen3.8-Max — The flagship of Qwen3.8 model
2. Qwen3.7-Plus
3. Qwen3.7-Max

### Flow
1. Navigate to `https://chat.qwen.ai`
2. Click "Начать" (text match)
3. Wait for `[class*="model-selector-text"]`
4. Click to open dropdown
5. Read `[class*="model-item-name"]` elements

## ChatGPT (OpenAI)

### Issue
- Requires login to show model list
- Shows only "ChatGPT" button without dropdown options
- Cookie/promo popups block interaction

### Recommendation
- Defer to post-MVP
- Require user to be logged in first
- May need different approach (API tokens instead of web automation)

## Implementation Notes

### Selectors Must Be Vendor-Specific
Each vendor has completely different DOM structure. Generic selectors don't work.

### Localization Matters
- Kimi: Russian UI ("Новый чат", "Быстрый")
- Qwen: Russian UI ("Начать", "Qwen3.8-Max")
- Must try multiple text variants for "New Chat" button

### Dropdown Timing
- Custom dropdowns (not native `<select>`) need explicit wait after click
- Kimi: ~2s animation
- Qwen: ~1s animation
- Must wait for items to appear before reading
