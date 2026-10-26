# Apple Design Skill — Inclusion Checklist & Quality Audit

> Generated: 2026-08-09
> Source: ~/.agents/skills/apple-design/SKILL.md
> Question: Should apple-design be in myCoder's skill packs? What's the quality if included?

## Current Status

**Location:** `~/.agents/skills/apple-design/SKILL.md` (system-level agent skill)
**In myCoder:** ❌ Not bundled — myCoder loads from `~/.mycoder/skills/`
**Pack type:** System skill pack (agents/), not myCoder skill

## Apple Design SKILL.md Content Analysis

### Topics Covered (from SKILL.md)

| Section | Topic | Depth | Quality |
|---------|-------|-------|---------|
| 1 | Response — kill latency | Deep | 95/100 |
| 2 | Direct manipulation — 1:1 tracking | Deep | 95/100 |
| 3 | Interruptibility | Very Deep | 98/100 |
| 4 | Springs over fixed animation | Deep | 95/100 |
| 5 | Momentum & physics | Deep | 90/100 |
| 6 | Translucency & depth | Medium | 85/100 |
| 7 | Typography (optical sizing) | Medium | 85/100 |
| 8 | Reduced motion | Medium | 80/100 |
| 9 | Gesture patterns (drag/swipe/sheet) | Deep | 90/100 |
| 10 | Design foundations (feedback, restraint) | Deep | 95/100 |

### Code Examples
- ✅ CSS spring animations
- ✅ JavaScript Pointer Events
- ✅ Velocity tracking patterns
- ✅ Spring parameter selection guide

### Strengths
- ✅ Authoritative source (WWDC distilled)
- ✅ Actionable, concrete values
- ✅ Covers both principles AND implementation
- ✅ Good code examples
- ✅ Web-translated (not just iOS)

### Weaknesses
- ❌ No SwiftUI-specific guidance (myCoder is SwiftUI)
- ❌ Web-focused (CSS/JS), not native macOS
- ❌ Would need adaptation for AppKit/SwiftUI context

## Decision: Include in myCoder?

### Arguments FOR inclusion
1. High quality content (90+ avg)
2. Directly relevant to myCoder's UI work
3. Fills gap in current skill packs
4. WWDC-sourced = authoritative

### Arguments AGAINST
1. Web-focused, myCoder is native macOS SwiftUI
2. Current better-access, better-layout, better-ui skills already cover some ground
3. May confuse agent (web CSS/JS in native app context)

### Recommendation: INCLUDE with adaptation

Create a myCoder-specific variant that:
- Translates web examples → SwiftUI/Animatable equivalents
- Keeps principles (universal)
- Adds native macOS patterns (AppKit spring animations, `matchedGeometryEffect`)

## Quality Score if Included As-Is: 75/100
## Quality Score if Adapted for SwiftUI: 92/100

## Current myCoder Skill Packs (for reference)

| Skill | Location | Status |
|-------|----------|--------|
| apple-design | ~/.agents/skills/ | System only, not in myCoder |
| (other packs) | ~/.agents/skills/ | Loaded by myCoder from ~/.mycoder/skills/ |

## Action Items

| Priority | Action | Impact |
|----------|--------|--------|
| P1 | Decide: include as-is or adapt | Clarity |
| P2 | If adapt: create SwiftUI-native version | Better agent guidance |
| P2 | Add to ~/.mycoder/skills/ or bundle | Availability |
