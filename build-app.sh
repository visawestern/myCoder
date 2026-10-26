#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# build-app.sh — Build myCoder.app with explicit semantic-version bumping.
#
# Normal builds are reproducible and do not mutate version metadata.
# A release bump is explicit: ./build-app.sh --bump [patch|minor|major].
# The selected release operation increments the marketing version once and
# increments CFBundleVersion once. There is no hidden/double bump.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="myCoder"
APP_BUNDLE="myCoder.app"
BUILD_DIR=".build/release"
RESOURCES_DIR="myCoder/Resources"
INFO_PLIST="$RESOURCES_DIR/Info.plist"

SKIP_TESTS=0
BUMP_KIND=""
PARALLEL=0

while (($# > 0)); do
    case "$1" in
        --skip-tests)
            SKIP_TESTS=1
            shift
            ;;
        --no-bump)
            BUMP_KIND=""
            shift
            ;;
        --bump)
            BUMP_KIND="patch"
            shift
            if (($# > 0)) && [[ "$1" != --* ]]; then
                case "$1" in
                    major|minor|patch) BUMP_KIND="$1"; shift ;;
                    *) echo "Unknown bump kind: $1 (use major, minor, or patch)"; exit 2 ;;
                esac
            fi
            ;;
        --bump=major|--bump=minor|--bump=patch)
            BUMP_KIND="${1#*=}"
            shift
            ;;
        --parallel)
            PARALLEL=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 2
            ;;
    esac
done

# ── Platform/toolchain preflight ─────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
    echo "━━━ ❌ myCoder build requires macOS (SwiftUI/AppKit/WebKit)."
    echo "━━━    Current platform: $(uname -s). Run this script on a macOS runner."
    exit 3
fi
if [ ! -x /usr/libexec/PlistBuddy ] || ! command -v swift >/dev/null 2>&1 || ! command -v xcodebuild >/dev/null 2>&1; then
    echo "━━━ ❌ myCoder build requires Xcode command-line tools and Swift on macOS."
    echo "━━━    Install/select Xcode, then re-run ./build-app.sh."
    exit 3
fi

# ── Version metadata ─────────────────────────────────────────
SHORT_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "0.1.0")
BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "0")
echo "━━━ Current: v$SHORT_VER (build $BUILD_NUM)"

# Normalize and bump one semantic version component only when explicitly asked.
version_parts=(${SHORT_VER//./ })
MAJOR="${version_parts[0]:-0}"
MINOR="${version_parts[1]:-0}"
PATCH="${version_parts[2]:-0}"
if ! [[ "$MAJOR" =~ ^[0-9]+$ && "$MINOR" =~ ^[0-9]+$ && "$PATCH" =~ ^[0-9]+$ ]]; then
    echo "━━━ ❌ Invalid semantic version in $INFO_PLIST: $SHORT_VER"
    exit 2
fi
if ! [[ "$BUILD_NUM" =~ ^[0-9]+$ ]]; then
    echo "━━━ ❌ Invalid numeric build number in $INFO_PLIST: $BUILD_NUM"
    exit 2
fi

if [ -n "$BUMP_KIND" ]; then
    case "$BUMP_KIND" in
        major) NEW_SHORT="$((MAJOR + 1)).0.0" ;;
        minor) NEW_SHORT="${MAJOR}.$((MINOR + 1)).0" ;;
        patch) NEW_SHORT="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
    esac
    NEW_BUILD=$((BUILD_NUM + 1))
    echo "━━━ Release bump ($BUMP_KIND): v$SHORT_VER → v$NEW_SHORT; build $BUILD_NUM → $NEW_BUILD"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_SHORT" "$INFO_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"
else
    NEW_SHORT="$SHORT_VER"
    NEW_BUILD="$BUILD_NUM"
    echo "━━━ No version bump (use --bump [patch|minor|major] for a release)"
fi

# ── Tests (optional — never block a build check) ─────────────
if [ "$SKIP_TESTS" -eq 1 ]; then
    echo "━━━ Skipping tests (--skip-tests)"
else
    echo "━━━ Running tests… (failures are reported but do NOT abort the build)"
    if swift test; then
        echo "━━━ Tests passed."
    else
        echo "━━━ ⚠️  Tests failed — continuing to build anyway (see output above)."
    fi
fi

# ── Build release ────────────────────────────────────────────
echo "━━━ Building release…"
if [ "$PARALLEL" -eq 1 ]; then
    CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
    BUILD_ARGS="--jobs $CORES"
    OPT_FLAG="-O"
    echo "    (parallel: $CORES jobs, -O optimization)"
else
    BUILD_ARGS="--jobs 1"
    OPT_FLAG="-Onone"
    echo "    (single-thread, -Onone — avoids Swift 6.3 deadlock)"
fi

if ! swift build -c release --product "$APP_NAME" $BUILD_ARGS -Xswiftc -no-whole-module-optimization -Xswiftc "$OPT_FLAG"; then
    echo ""
    echo "━━━ ❌ BUILD FAILED. Full compiler output is above (not truncated)."
    echo "━━━    Fix the errors and re-run ./build-app.sh"
    exit 1
fi

# ── Assemble the .app bundle in the repo root ────────────────
echo "━━━ Assembling $APP_BUNDLE (clean)…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "━━━ Copying resource bundles…"
shopt -s nullglob
copied=0
for b in "$BUILD_DIR"/*.bundle; do
    cp -R "$b" "$APP_BUNDLE/Contents/Resources/"
    echo "    + $(basename "$b")"
    copied=$((copied + 1))
done
shopt -u nullglob
if [ "$copied" -eq 0 ]; then
    echo "    (no SPM resource bundles found — catalogs may not load)"
fi

# ── Code signing ──────────────────────────────────────────────
# A fresh unsigned bundle triggers Gatekeeper/XProtect on every launch.
# Use an explicit identity via CODESIGN_IDENTITY, otherwise prefer a local
# Apple Development identity, then fall back to ad-hoc signing.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development:/{print $2; exit}')
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application:/{print $2; exit}')
fi
if [ -n "$SIGN_IDENTITY" ]; then
    echo "━━━ Signing with: $SIGN_IDENTITY"
    if ! codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"; then
        echo "━━━ ⚠️  Signing failed — leaving the bundle unsigned"
    elif codesign --verify --deep --strict "$APP_BUNDLE"; then
        echo "━━━ ✅ Signature verified"
    else
        echo "━━━ ⚠️  Signature verification failed"
    fi
else
    echo "━━━ ⚠️  No code-signing identity found; macOS may re-check the app on launch"
fi

BIN_SIZE=$(stat -f "%z" "$BUILD_DIR/$APP_NAME" 2>/dev/null || stat --format="%s" "$BUILD_DIR/$APP_NAME" 2>/dev/null || echo "0")
echo "━━━ ✅ Built v$NEW_SHORT (build $NEW_BUILD) — $((BIN_SIZE / 1024)) KB"
echo "━━━ App: $SCRIPT_DIR/$APP_BUNDLE"
echo "━━━ Run: open '$APP_BUNDLE'"
