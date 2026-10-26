#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# setup-reranker.sh — local rerank backend for myCoder (Phase 5, 5500M).
#
# Installs llama.cpp (Metal build), verifies a reranker GGUF, starts
# `llama-server` with full GPU offload, and smoke-tests the exact
# /rerank contract myCoder's URLSessionRerankTransport speaks.
#
# Usage:
#   MODEL_GGUF_URL=<hf-url> ./scripts/setup-reranker.sh [--bench] [--port 8080]
#
# MODEL_GGUF_URL is required: pick a Qwen3-Reranker-0.6B (or 4B) Q8/Q4 GGUF
# from Hugging Face yourself and pass its resolve URL — community quant URLs
# rotate, so the script refuses to guess one (it fails honestly instead).
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

PORT=8080
BENCH=0
MODEL_URL="${MODEL_GGUF_URL:-}"
MODEL_DIR="${HOME}/.mycoder/models"

while (($# > 0)); do
    case "$1" in
        --bench) BENCH=1; shift ;;
        --port) PORT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 2 ;;
    esac
done

if [ "$(uname -s)" != "Darwin" ]; then
    echo "❌ reranker setup requires macOS with Metal."
    exit 3
fi

if ! system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Metal Support: Metal"; then
    echo "❌ No Metal-capable GPU found."
    exit 3
fi
echo "━━━ Metal GPU present:"
system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|VRAM \(Total\)" | head -n 4

if ! command -v llama-server >/dev/null 2>&1; then
    echo "━━━ Installing llama.cpp (may take a while on first run)…"
    brew install llama.cpp
else
    echo "━━━ llama-server already installed: $(command -v llama-server)"
fi

if [ -z "$MODEL_URL" ]; then
    echo ""
    echo "❌ MODEL_GGUF_URL is not set — refusing to guess a model URL."
    echo "   Pick a Qwen3-Reranker GGUF (0.6B-Q8 default, 4B-Q4 optional) on"
    echo "   Hugging Face and re-run, e.g.:"
    echo "     MODEL_GGUF_URL=https://huggingface.co/<org>/<repo>/resolve/main/<file>.gguf \\"
    echo "       ./scripts/setup-reranker.sh --bench"
    exit 2
fi

mkdir -p "$MODEL_DIR"
MODEL_FILE="$MODEL_DIR/$(basename "$MODEL_URL" | cut -d? -f1)"
if [ ! -f "$MODEL_FILE" ]; then
    echo "━━━ Downloading $(basename "$MODEL_FILE")…"
    curl -fL --retry 3 -o "$MODEL_FILE" "$MODEL_URL"
else
    echo "━━━ Model cached: $MODEL_FILE"
fi
SIZE=$(stat -f "%z" "$MODEL_FILE" 2>/dev/null || stat --format="%s" "$MODEL_FILE")
if [ "$SIZE" -lt 100000000 ]; then
    echo "❌ $MODEL_FILE is only $SIZE bytes — not a real GGUF. Delete it and check the URL."
    exit 2
fi
echo "━━━ Model OK ($((SIZE / 1024 / 1024)) MB)"

echo "━━━ Endpoint check: 'llama-server --help | grep -i rerank'"
if ! llama-server --help 2>&1 | grep -qi "rerank"; then
    echo "❌ This llama.cpp build has no rerank support — update llama.cpp and retry."
    exit 2
fi
llama-server --help 2>&1 | grep -i "rerank" | head -n 5

echo "━━━ Starting llama-server on :$PORT (full Metal offload)…"
pkill -f "llama-server.*--port $PORT" 2>/dev/null || true
nohup llama-server -m "$MODEL_FILE" --port "$PORT" -ngl 100 --reranking \
    > /tmp/mycoder-reranker.log 2>&1 &
echo "$!" > /tmp/mycoder-reranker.pid
echo "━━━ pid $(cat /tmp/mycoder-reranker.pid), log /tmp/mycoder-reranker.log"

echo "━━━ Waiting for /health…"
for i in $(seq 1 60); do
    if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        echo "━━━ ✅ server healthy after ~${i}s"
        break
    fi
    sleep 2
    if [ "$i" = 60 ]; then
        echo "❌ server did not become healthy — see /tmp/mycoder-reranker.log"
        exit 2
    fi
done

echo "━━━ Smoke test: POST /rerank (myCoder contract)…"
RESP=$(curl -sf "http://127.0.0.1:$PORT/rerank" \
    -H "Content-Type: application/json" \
    -d '{"query":"SQLite WAL history","documents":["the project uses SQLite WAL mode","lunch preferences"]}') \
    || { echo "❌ /rerank rejected our contract — compare with URLSessionRerankTransport and fix one side."; exit 2; }
echo "━━━ response: $RESP"
echo "$RESP" | grep -q "scores" \
    && echo "━━━ ✅ contract OK — myCoder can use http://127.0.0.1:$PORT" \
    || { echo "❌ response has no {scores} — fix transport or server flags."; exit 2; }

if [ "$BENCH" = 1 ]; then
    echo "━━━ Bench: 20 docs × 5 runs (measure ms/run, compare with MemoryScorer)…"
    python3 - "$PORT" <<'EOF'
import json, time, urllib.request
port = __import__('sys').argv[1]
docs = ["the project uses SQLite WAL mode for history"] + [f"filler document number {i} about unrelated things" for i in range(19)]
body = json.dumps({"query": "SQLite WAL history", "documents": docs}).encode()
ts = []
for _ in range(5):
    t0 = time.time()
    req = urllib.request.Request(f"http://127.0.0.1:{port}/rerank", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        out = json.loads(r.read())
    ts.append((time.time() - t0) * 1000)
    assert out["scores"][0] == max(out["scores"]), f"expected doc0 on top: {out['scores'][:3]}"
print(f"━━━ ✅ bench: min {min(ts):.0f}ms / median {sorted(ts)[2]:.0f}ms / max {max(ts):.0f}ms per 20-doc rerank; doc0 ranked first")
EOF
fi

echo "━━━ Done. Stop the server with: kill $(cat /tmp/mycoder-reranker.pid)"
