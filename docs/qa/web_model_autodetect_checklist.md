# Web Model Auto-Detection — Feature Checklist & Quality Audit

> Generated: 2026-08-09
> Source: WebModelDiscovery.swift, WebModelListParser.swift, WebChatDriver.swift, web_providers_catalog.json
> Problem: Models don't pick up session, can't wait for full page load, can't find models on page

## Architecture Overview

```
WebChatProvider config
├── chatURL (e.g. https://chat.openai.com)
├── vendor.id (e.g. "openai", "anthropic", "google")
└── WebProviderCatalog.selectors.modelDropdown (per-vendor)

On send:
runWebChatTurn(config, text, assistantID)
├── bridge.navigate(to: config.chatURL)
├── wait for input selector (30 × 500ms = 15s)
├── WebModelDiscovery.discover(using: bridge, dropdownSelector:, vendor:)
│   ├── JavaScript injection to find model dropdown
│   ├── Parse DOM for model names
│   └── Return [WebDiscoveredModel]
└── driver.runTurn(userMessage:, isFirstMessage:)
    ├── inject preamble (first turn)
    ├── type text into input
    ├── click send
    └── wait for response via DOM polling
```

## Feature Matrix

| Feature | Function | Current Status | Quality | Notes |
|---------|----------|---------------|---------|-------|
| Navigate to chat URL | `bridge.navigate()` | ✅ Works | 90/100 | Standard WKWebView nav |
| Wait for input selector | loop 30×500ms | ⚠️ Fragile | 45/100 | **Fixed wait, doesn't wait for full page** |
| Model discovery from catalog | `WebProviderCatalog.selectors` | ⚠️ Incomplete | 40/100 | **Only some vendors have dropdown selectors** |
| Model discovery JS injection | `WebModelDiscovery.discover()` | ⚠️ Fragile | 35/100 | **Depends on DOM structure, breaks on redesign** |
| Parse model names from DOM | `WebModelListParser` | ⚠️ Partial | 40/100 | **Regex/JS based, vendor-specific** |
| Restore session cookies | `WebSessionManager.restore()` | ✅ Works | 75/100 | Works but no feedback |
| Auto-detect and save models | `WebProviderStore.upsert()` | ⚠️ Partial | 35/100 | **Only if discovery succeeds** |
| Manual model selection | UI dropdown | ✅ Works | 70/100 | Works if models exist |
| Show discovered models in UI | `ProvidersSettingsView` | ⚠️ Missing | 30/100 | **No indication of discovery success/failure** |

## Root Cause Analysis: Model Detection Fails

### Problem 1: No wait for full page load
```swift
// ChatPanelView.swift line 942-952
var ready = false
for _ in 0..<30 {
    if (try? await bridge.exists(selector: selectors.input)) ?? false {
        ready = true
        break
    }
    await bridge.wait(ms: 500)
}
```
- Only checks for **input element**, not full page readiness
- Modern chat apps load models AFTER input (async hydration)
- Input may exist but model dropdown not yet populated

### Problem 2: Catalog selectors incomplete
```json
// web_providers_catalog.json — only some vendors have modelDropdown
{
  "openai": { "modelDropdown": "..." },
  "anthropic": { ... }  // ← may be missing
}
```
- If vendor not in catalog → `dropdownSelector = nil` → discovery skipped entirely
- No fallback generic discovery

### Problem 3: JavaScript injection is fragile
```swift
// WebModelDiscovery — injects JS to find dropdown
// Breaks when:
// - Site redesigns DOM
// - Model selector is not a <select> but custom component
// - Shadow DOM
// - Models loaded via API not in DOM
```

### Problem 4: No manual override / feedback
- If auto-detect fails → silent failure
- User doesn't know models weren't found
- No way to manually trigger "find models now"
- No way to see what was detected

### Problem 5: Session/cookie restoration not validated
- `WebSessionManager.restore()` restores cookies
- No check if session is actually valid
- User may appear "logged in" but session expired

## Quality Score: 38/100

### Strengths
- ✅ Clean separation (discovery, parsing, driver)
- ✅ Per-vendor catalog system
- ✅ Session cookie persistence

### Weaknesses
- ❌ **No full page load wait** (models load after input)
- ❌ **Incomplete catalog** (many vendors missing)
- ❌ **Fragile JS injection** (breaks on redesign)
- ❌ **No manual trigger** for model discovery
- ❌ **No success/failure feedback**
- ❌ **No session validity check**

## User Story: Expected Behavior

**As a user configuring a web provider:**
1. I add a web provider (URL + vendor)
2. The app navigates and waits for FULL page load (network idle, not just DOM element)
3. I see a compact status indicator (top bar or sidebar) showing:
   - 🟡 "Detecting models..."
   - 🟢 "Found: GPT-4o, GPT-4o-mini, o1-preview" (with count)
   - 🔴 "No models found — [Retry] [Manual Setup]"
4. If auto-detect fails, I can click "Retry" after page fully loads
5. I can manually trigger detection at any time
6. Selected model persists across sessions

## Recommended Fixes

| Priority | Fix | Impact |
|----------|-----|--------|
| P0 | Wait for network idle / full hydration, not just input | Models actually present |
| P0 | Compact detection status in header/sidebar | User sees progress |
| P0 | Manual "Detect Models" button | Recovery from failure |
| P1 | Retry mechanism with exponential backoff | Handles slow loads |
| P1 | Session validity probe before chat | Avoid sending to dead session |
| P2 | Generic fallback discovery (scan page text for model names) | Broader coverage |
| P2 | Per-vendor discovery strategies | More robust |
| P3 | Show discovered models with checkboxes | User can pick |
