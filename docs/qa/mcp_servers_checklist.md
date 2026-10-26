# MCP Servers Tab — Feature Checklist & Quality Audit

> Generated: 2026-08-09
> Source: MCPServersSettingsView.swift, MCPHealthCheckLogic.swift, AgentResourcesLoader.swift, AgentResourceRegistryManager.swift
> Problem: Tab loads slowly — health probes fire for every server on appear, no caching, no concurrency limit

## Architecture Overview

```
MCPServersSettingsView
├── onAppear → reloadServers() → AgentResourcesLoader.loadMCPServers()
│   └── parses ~/.mycoder/mcp.json
├── ForEach(server) → InstalledMCPRow(server)
│   └── .task(id: server.id) → refreshHealth()  ← FIRES ON EVERY APPEAR
│       ├── MCPRegistryManager.load()  (cache check)
│       └── if unknown → MCPHealthChecker.check()  ← HTTP/stdio probe
│           ├── probeHTTP(url)  ← can HANG on timeout
│           └── resolveStdioCommand(command)  ← PATH search
└── AgentResourceLibraryView(mode: .mcpServers)
    └── browse + install flow
```

## Feature Matrix

| Feature | Function | Current Status | Quality | Notes |
|---------|----------|---------------|---------|-------|
| Load configured servers | `AgentResourcesLoader.loadMCPServers()` | ✅ Works | 95/100 | Fast (local file parse) |
| Parse mcp.json | `parseMCPConfig(at:)` | ✅ Works | 90/100 | Handles missing file gracefully |
| Search/filter servers | `AgentResourcesLoader.filterEntries()` | ✅ Works | 95/100 | Case-insensitive, works |
| Health status dot | `InstalledMCPRow.healthStatus` | ⚠️ Slow | 40/100 | **Root cause: probes fire every appear, no concurrency limit** |
| Health probe HTTP | `MCPHealthCheckLogic.probeHTTP()` | ⚠️ Risky | 35/100 | **No timeout visible, can hang** |
| Health probe stdio | `MCPHealthCheckLogic.resolveStdioCommand()` | ✅ Works | 70/100 | PATH resolution, sync |
| Enable/disable server | `setDisabled(_:)` | ✅ Works | 85/100 | Writes mcp.json + registry |
| Remove server | `remove()` | ✅ Works | 85/100 | Removes from mcp.json + registry |
| Remove confirmation alert | alert dialog | ✅ Works | 90/100 | Shows path, cancel/confirm |
| AgentResourceLibraryView | browse + install | ✅ Works | 80/100 | Separate component, works |
| Registry persistence | `MCPRegistryManager` | ✅ Works | 75/100 | Persists health results |
| Cache check (avoid re-probe) | `MCPHealthCheckLogic.status()` | ⚠️ Partial | 50/100 | **Checks registry but still probes when unknown** |
| Disabled server handling | gray dot | ✅ Works | 80/100 | Shows muted when disabled |

## Root Cause Analysis: Slowness

### Problem 1: Health probes fire on every `.onAppear`
```swift
// Line 120: InstalledMCPRow
.task(id: server.id) {
    await refreshHealth()  // ← fires EVERY time view appears
}
```
- If user switches tabs and comes back → re-probes all servers
- No debounce, no "already checked" guard beyond registry cache

### Problem 2: No concurrency limit
- Each row runs `.task` independently
- 10 servers = 10 parallel HTTP requests
- If several have unreachable URLs → all hang until timeout

### Problem 3: `probeHTTP` has no visible timeout
```swift
// MCPHealthCheckLogic.swift line ~100
private static func probeHTTP(url: URL) async -> Bool {
    guard let request = URLRequest(url: url) else { return false }
    return try? await URLSession.shared.data(for: request)  // ← DEFAULT TIMEOUT
}
```
- Default URLSession timeout = 60s for request
- If server unreachable → 60s hang per server
- 5 unreachable servers × 60s = 5 minutes!

### Problem 4: Registry cache is per-row
- Each row loads `MCPRegistryManager.load(homeDirectory:)` independently
- N rows = N full JSON parses of registry file

## Quality Score: 55/100

### Strengths
- ✅ Clean SwiftUI architecture
- ✅ Proper file-based config (mcp.json)
- ✅ Registry persistence for health results
- ✅ Enable/disable/remove all work

### Weaknesses
- ❌ **Health probes block UI on appear** (critical)
- ❌ **No timeout on HTTP probe** (can hang 60s+)
- ❌ **No concurrency limit** (N parallel hangs)
- ❌ **No cancellation** when row disappears
- ❌ **Re-probes every appear** (no session cache)

## Recommended Fixes

| Priority | Fix | Impact |
|----------|-----|--------|
| P0 | Add explicit timeout (5s) to probeHTTP | Eliminates 60s hangs |
| P0 | Limit concurrent probes (max 3-4) | Prevents resource exhaustion |
| P1 | Cache health results for session duration | Avoids re-probe on tab switch |
| P1 | Cancel probe task when row disappears | Saves resources |
| P2 | Show "checking..." state during probe | Better UX |
| P2 | Debounce probe (don't fire if checked <5min ago) | Reduces unnecessary probes |
