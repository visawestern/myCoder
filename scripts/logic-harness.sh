#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# logic-harness.sh — Ground-truth Foundation-only test harness (Swift on Linux)
#
# MyCoder's app target imports SwiftUI/AppKit/WebKit and CANNOT compile on Linux.
# This harness compiles ONLY the Foundation-only Services/Models and runs their
# swift-testing suites, producing a REPRODUCIBLE @Test / pass / fail count in
# EVAL.md — the one number every doc should cite instead of a hand-typed guess.
#
# Unlike the legacy scripts/test-logic.sh (which hard-coded a whitelist and a
# stale repo path), this AUTO-DISCOVERS every *.swift under Sources that imports
# only Foundation (no SwiftUI/AppKit/WebKit/SQLite/Cocoa) and every test file that
# does the same, so coverage tracks the tree instead of drifting from it.
#
# Usage: scripts/logic-harness.sh        (run from repo root; writes ./EVAL.md)
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
EVAL="$REPO/EVAL.md"
SWIFT_VER="6.0.3"
UBUNTU="ubuntu24.04"

log() { echo "━━━ $*"; }

# ── 1. Ensure a Swift toolchain ─────────────────────────────────────────────
if ! command -v swift >/dev/null 2>&1; then
  log "Swift not found — installing Swift $SWIFT_VER for $UBUNTU"
  TARBALL="swift-${SWIFT_VER}-RELEASE-${UBUNTU}"
  URL="https://download.swift.org/swift-${SWIFT_VER}-release/${UBUNTU//./}/swift-${SWIFT_VER}-RELEASE/${TARBALL}.tar.gz"
  SWIFT_ROOT="${HOME}/.local/swift/${SWIFT_VER}"
  if [ -x "$SWIFT_ROOT/usr/bin/swift" ]; then
    export PATH="$SWIFT_ROOT/usr/bin:$PATH"
  else
    mkdir -p "$SWIFT_ROOT" || {
      log "❌ Cannot create user-local Swift directory: $SWIFT_ROOT"
      exit 3
    }
    TMP_TARBALL="${TMPDIR:-/tmp}/swift-${SWIFT_VER}.tar.gz"
    if ! curl -fL --retry 2 --connect-timeout 15 --max-time 900 "$URL" -o "$TMP_TARBALL"; then
      log "❌ Could not download Swift toolchain from $URL"
      exit 3
    fi
    if ! tar -xzf "$TMP_TARBALL" -C "$SWIFT_ROOT" --strip-components=1; then
      log "❌ Swift archive is incomplete or invalid: $TMP_TARBALL"
      exit 3
    fi
    export PATH="$SWIFT_ROOT/usr/bin:$PATH"
  fi
fi
log "Using $(swift --version 2>&1 | head -1)"

# ── 2. Assemble an ephemeral Foundation-only package ────────────────────────
PKG="${TMPDIR:-/tmp}/mycoder-logic-harness"
rm -rf "$PKG"
mkdir -p "$PKG/Sources/MyCoderLogic" "$PKG/Tests/MyCoderLogicTests"
cp -r "$REPO/myCoder/Sources/Resources" "$PKG/Sources/MyCoderLogic/Resources" 2>/dev/null || true

# A file is Foundation-only if it does NOT import a macOS-only framework.
is_foundation_only() {
  ! grep -Eq '^[[:space:]]*(import|#if canImport\()[[:space:]]*(SwiftUI|AppKit|WebKit|Cocoa|SQLite)\b' "$1"
}

# Test-only stub for PlusMenuItem (the real one carries UI deps).
cat > "$PKG/Sources/MyCoderLogic/PlusMenuItemStub.swift" <<'STUB'
import Foundation
enum PlusMenuItem: String, CaseIterable, Equatable {
    case addAttachment, addPhoto, insertMention, insertCommand, insertSession
}
STUB

src_count=0
for f in "$REPO"/myCoder/Sources/Services/*.swift "$REPO"/myCoder/Sources/Models/*.swift; do
  [ -e "$f" ] || continue
  if is_foundation_only "$f"; then
    ln -sf "$f" "$PKG/Sources/MyCoderLogic/$(basename "$f")"
    src_count=$((src_count + 1))
  fi
done

test_count_files=0
for f in "$REPO"/myCoder/Tests/*.swift; do
  [ -e "$f" ] || continue
  if is_foundation_only "$f"; then
    ln -sf "$f" "$PKG/Tests/MyCoderLogicTests/$(basename "$f")"
    test_count_files=$((test_count_files + 1))
  fi
done

cat > "$PKG/Package.swift" <<'PKGEOF'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "myCoder",
    platforms: [.macOS(.v13)],
    products: [.library(name: "myCoder", targets: ["MyCoder"])],
    targets: [
        .target(name: "myCoder", path: "Sources/MyCoderLogic", resources: [.process("Resources")]),
        .testTarget(name: "myCoderTests", dependencies: ["myCoder"], path: "Tests/MyCoderLogicTests")
    ]
)
PKGEOF

log "Discovered $src_count Foundation-only source files, $test_count_files test files"

# ── 3. Build + test, capturing output ───────────────────────────────────────
cd "$PKG"
LOG="${TMPDIR:-/tmp}/mycoder-harness.log"
log "swift test --no-parallel"
set +e
swift test --no-parallel 2>&1 | tee "$LOG"
TEST_RC=${PIPESTATUS[0]}
set -e 2>/dev/null || true

# ── 4. Parse results ────────────────────────────────────────────────────────
# swift-testing prints e.g. "Test run with 1234 tests passed after ..." or
# "... N tests failed". Fall back to counting @Test declarations if unparsed.
DECLARED=$(grep -rhoE '@Test\b' "$PKG/Tests" | wc -l | tr -d ' ')
SUITES=$(grep -rhoE '@Suite\b' "$PKG/Tests" | wc -l | tr -d ' ')
PASSED=$(grep -oE 'with [0-9]+ test[s]? passed' "$LOG" | grep -oE '[0-9]+' | tail -1)
FAILED=$(grep -oE '[0-9]+ test[s]? failed' "$LOG" | grep -oE '[0-9]+' | tail -1)
EXECUTED=$(grep -oE 'with [0-9]+ test' "$LOG" | grep -oE '[0-9]+' | tail -1)
[ -z "${PASSED:-}" ] && PASSED="?"
[ -z "${FAILED:-}" ] && FAILED="0"
[ -z "${EXECUTED:-}" ] && EXECUTED="?"

if [ "$TEST_RC" -eq 0 ]; then VERDICT="✅ PASS"; else VERDICT="❌ FAIL (rc=$TEST_RC)"; fi

# ── 5. Emit EVAL.md ─────────────────────────────────────────────────────────
cat > "$EVAL" <<EOF
# EVAL — MyCoder Foundation-only logic harness

**Verdict:** $VERDICT
**Generated:** $(date -u +"%Y-%m-%dT%H:%M:%SZ") by \`scripts/logic-harness.sh\`
**Swift:** $(swift --version 2>&1 | head -1)

## Ground-truth numbers (reproducible)

| Metric | Value |
|--------|-------|
| Foundation-only source files compiled | $src_count |
| Foundation-only test files run | $test_count_files |
| \`@Test\` declarations (this harness scope) | $DECLARED |
| \`@Suite\` declarations (this harness scope) | $SUITES |
| Tests executed (runtime, incl. parameterized) | $EXECUTED |
| Tests passed | $PASSED |
| Tests failed | $FAILED |

## Scope & honest limits

- The macOS app target (SwiftUI/AppKit/WebKit/SQLite) is **not** compiled here —
  it cannot build on Linux. This harness covers the pure logic only.
- Coverage is **auto-discovered** (every Foundation-only file under Sources/Tests),
  not a hand-maintained whitelist, so it tracks the tree.
- This is the ONLY reproducible test number for the project. Any documentation
  count that disagrees with this file is stale.

## Tail of test output

\`\`\`
$(tail -25 "$LOG")
\`\`\`
EOF

log "Wrote $EVAL (verdict: $VERDICT)"
exit "$TEST_RC"
