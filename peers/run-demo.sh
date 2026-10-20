#!/usr/bin/env bash
# A0 + B0 integration demo: .scip -> cbm DB -> cbm HTTP -> Svelte UI.
set -euo pipefail

PEERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBM_REPO="$(cd "$PEERS/.." && pwd)"
RULES="$(cd "$CBM_REPO/.." && pwd)"
FIX="$PEERS/fixtures/callgraph-ts-hard"
OUT="${DEMO_OUT:-/tmp/code-graph-demo}"
CACHE="${CBM_CACHE_DIR:-$OUT/cache}"
PROJECT="${DEMO_PROJECT:-fixture-hard-scip}"
CBM_PORT="${CBM_PORT:-9751}"
UI_PORT="${UI_PORT:-5173}"
REACT_PORT="${REACT_PORT:-9749}"
BUN="${BUN:-$HOME/.bun/bin/bun}"
CBM="$RULES/cbm-runtime/node_modules/.bin/codebase-memory-mcp"
SCIP_PRINT="${SCIP_PRINT:-$HOME/tools/scip/scip}"
SCIP="$OUT/hard.scip"

mkdir -p "$OUT" "$CACHE"

CBM_PID=""
UI_PID=""
PROXY_PID=""
cleanup() {
  if [ -n "$CBM_PID" ]; then kill -- -"$CBM_PID" 2>/dev/null || true; fi
  if [ -n "$UI_PID" ]; then kill "$UI_PID" 2>/dev/null || true; fi
  if [ -n "$PROXY_PID" ]; then kill -- -"$PROXY_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
[ -x "$BUN" ] || { echo "missing bun: $BUN" >&2; exit 1; }
[ -x "$CBM" ] || { echo "missing cbm: $CBM (run peers/install.sh)" >&2; exit 1; }

# 1. SCIP index (only if absent).
if [ ! -f "$SCIP" ]; then
  need node
  echo "== scip index"
  node "$RULES/scip-typescript/dist/src/main.js" index \
    --cwd "$FIX" --output "$SCIP" --no-progress-bar
fi

# 2. writer -> cbm v3 SQLite.
if [ ! -d "$CBM_REPO/tools/scip-cbm-writer/node_modules" ]; then
  echo "== bun install (scip-cbm-writer)"
  ( cd "$CBM_REPO/tools/scip-cbm-writer" && exec "$BUN" install )
fi
echo "== scip-cbm-writer"
( cd "$CBM_REPO/tools/scip-cbm-writer" && exec "$BUN" run src/cli.ts "$SCIP" \
  --project "$PROJECT" --root "$FIX" --cache-dir "$CACHE" \
  --ext "$OUT/index.ext.jsonl" )

# 3. cbm HTTP (skip if already listening).
if ! curl -sf --max-time 1 "http://127.0.0.1:$CBM_PORT/api/tree?project=$PROJECT" >/dev/null; then
  echo "== cbm HTTP :$CBM_PORT"
  setsid bash -c 'exec "$0" --ui=true --port="$1"' "$CBM" "$CBM_PORT" \
    < <(sleep infinity) > "$OUT/cbm.log" 2>&1 &
  CBM_PID=$!
  for _ in $(seq 1 30); do
    curl -sf --max-time 1 "http://127.0.0.1:$CBM_PORT/api/tree?project=$PROJECT" >/dev/null && break
    sleep 0.3
  done
fi

# 4. React graph-ui on 0.0.0.0 (cbm itself only binds loopback).
if ! curl -sf --max-time 1 "http://127.0.0.1:$REACT_PORT/" >/dev/null; then
  echo "== React proxy :$REACT_PORT -> 127.0.0.1:$CBM_PORT"
  setsid env PROXY_HOST=0.0.0.0 PROXY_PORT="$REACT_PORT" CBM_UPSTREAM_HOST=127.0.0.1 CBM_UPSTREAM_PORT="$CBM_PORT" \
    "$BUN" "$PEERS/react-ui-proxy.ts" > "$OUT/react-proxy.log" 2>&1 &
  PROXY_PID=$!
  for _ in $(seq 1 30); do
    curl -sf --max-time 1 "http://127.0.0.1:$REACT_PORT/" >/dev/null && break
    sleep 0.3
  done
fi

# 5. UI dev server.
if [ ! -d "$CBM_REPO/graph-ui-svelte/node_modules" ]; then
  echo "== bun install (code-graph)"
  ( cd "$CBM_REPO/graph-ui-svelte" && exec "$BUN" install )
fi
echo "== UI :$UI_PORT"
( cd "$CBM_REPO/graph-ui-svelte" && CBM_HTTP="http://127.0.0.1:$CBM_PORT" exec "$BUN" run dev -- --host 0.0.0.0 --port "$UI_PORT" ) &
UI_PID=$!

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "open http://${HOST_IP:-127.0.0.1}:$UI_PORT/  (also 127.0.0.1 locally)"
echo "React: http://${HOST_IP:-127.0.0.1}:$REACT_PORT/"
echo "click 'cbm HTTP'; project=$PROJECT; symbol=$PROJECT.src.features.useAlias"
echo "Ctrl-C to stop."
wait "$UI_PID"
