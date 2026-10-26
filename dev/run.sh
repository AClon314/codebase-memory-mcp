#!/usr/bin/env bash
# Current dev loop: hard fixture -> SCIP -> scip-cbm-writer -> cbm HTTP -> GUI.
#
#   ./run.sh              build the graph, start cbm, then graph-ui-svelte (code-server)
#   ./run.sh --vite       build the graph, start cbm, then the standalone Vite app
#   ./run.sh --setup      install cbm runtime + writer dependencies (network)
set -euo pipefail

DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBM_REPO="$(cd "$DEV/.." && pwd)"
RULES="$(cd "$CBM_REPO/.." && pwd)"
FIX="$DEV/fixtures/callgraph-ts-hard"
OUT="${CBM_DEV_OUT:-${DEMO_OUT:-/tmp/code-graph-demo}}"
CACHE="${CBM_CACHE_DIR:-$HOME/.cache/codebase-memory-mcp}"
PROJECT="${CBM_PROJECT:-${DEMO_PROJECT:-fixture-hard-scip}}"
CBM_PORT="${CBM_PORT:-}"
CBM_PROXY_PORT="${CBM_PROXY_PORT:-9750}"
UI_PORT="${UI_PORT:-5173}"
BUN="${BUN:-$HOME/.bun/bin/bun}"
CBM="$RULES/cbm-runtime/node_modules/.bin/codebase-memory-mcp"
SCIP="$OUT/hard.scip"
SCIP_INDEXER="${SCIP_INDEXER:-$RULES/scip-typescript/dist/src/main.js}"
SYMBOL="${CBM_SYMBOL:-$PROJECT.src.features.useAlias}"

MODE="gui"
CBM_PID=""
PROXY_PID=""
UI_PID=""

usage() {
  cat <<'EOF'
Usage: ./run.sh [gui|--vite|--setup]

  gui       (default) hard fixture -> SCIP -> writer -> cbm HTTP -> bun run gui
  --vite    same data steps, then `bun run dev` with /api proxied to cbm
  --setup   install cbm runtime and scip-cbm-writer dependencies (network)

Environment: CBM_DEV_OUT, CBM_CACHE_DIR, CBM_PROJECT, CBM_PORT, CBM_PROXY_PORT,
             UI_PORT, SCIP_INDEXER, BUN, CBM_SYMBOL, VITE_CBM_BASE
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }
}

cleanup() {
  local pid
  for pid in "$UI_PID" "$PROXY_PID" "$CBM_PID"; do
    [ -n "$pid" ] || continue
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

while [ $# -gt 0 ]; do
  case "$1" in
    gui) MODE="gui" ;;
    --vite|vite) MODE="vite" ;;
    --setup|setup) MODE="setup" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -x "$BUN" ] || { echo "missing bun: $BUN" >&2; exit 1; }

# An existing cbm daemon pins both its cache root and ui_port. Prefer the
# configured port so the script joins an already-running daemon.
if [ -z "$CBM_PORT" ]; then
  if [ -x "$CBM" ]; then
    CBM_PORT="$("$CBM" config get ui_port 2>/dev/null | tail -n 1 | tr -cd '0-9')" || true
  fi
  CBM_PORT="${CBM_PORT:-9749}"
fi

if [ "$MODE" = "setup" ]; then
  need node
  echo "== cbm runtime"
  bash "$DEV/install.sh"
  echo "== scip-cbm-writer deps"
  ( cd "$CBM_REPO/tools/scip-cbm-writer" && exec "$BUN" install )
  echo "done. Build $RULES/scip-typescript if it is not built yet."
  exit 0
fi

mkdir -p "$OUT" "$CACHE"

prepare_data() {
  if [ ! -f "$SCIP" ]; then
    need node
    [ -f "$SCIP_INDEXER" ] || {
      echo "missing SCIP indexer: $SCIP_INDEXER" >&2
      echo "build $RULES/scip-typescript or set SCIP_INDEXER" >&2
      exit 1
    }
    echo "== scip index: $FIX"
    node "$SCIP_INDEXER" index \
      --cwd "$FIX" --output "$SCIP" --no-progress-bar
  else
    echo "== reusing SCIP index: $SCIP"
  fi

  [ -d "$CBM_REPO/tools/scip-cbm-writer/node_modules" ] || {
    echo "missing scip-cbm-writer deps; run ./run.sh --setup" >&2
    exit 1
  }
  echo "== scip-cbm-writer -> $CACHE/$PROJECT.db"
  ( cd "$CBM_REPO/tools/scip-cbm-writer" && exec "$BUN" run src/cli.ts "$SCIP" \
      --project "$PROJECT" --root "$FIX" --cache-dir "$CACHE" \
      --ext "$OUT/index.ext.jsonl" )
}

start_cbm() {
  local base="http://127.0.0.1:$CBM_PORT"
  if curl -sf --max-time 1 "$base/api/tree?project=$PROJECT" >/dev/null; then
    echo "== cbm already serves $PROJECT on :$CBM_PORT"
    return 0
  fi
  if curl -sf --max-time 1 "$base/api/config" >/dev/null; then
    echo "error: $base is already in use but does not serve project $PROJECT" >&2
    echo "       stop it or set CBM_PORT" >&2
    exit 1
  fi
  [ -x "$CBM" ] || {
    echo "missing cbm: $CBM" >&2
    echo "run ./run.sh --setup" >&2
    exit 1
  }

  echo "== cbm HTTP :$CBM_PORT (cache: $CACHE)"
  CBM_CACHE_DIR="$CACHE" setsid bash -c 'exec "$0" --ui=true --port="$1"' \
    "$CBM" "$CBM_PORT" < <(sleep infinity) > "$OUT/cbm.log" 2>&1 &
  CBM_PID=$!
  for _ in $(seq 1 50); do
    if curl -sf --max-time 1 "$base/api/tree?project=$PROJECT" >/dev/null; then
      return 0
    fi
    if ! kill -0 "$CBM_PID" 2>/dev/null; then
      echo "cbm exited; see $OUT/cbm.log" >&2
      exit 1
    fi
    sleep 0.2
  done
  echo "cbm did not become ready; see $OUT/cbm.log" >&2
  echo "hint: a running cbm daemon pins CBM_CACHE_DIR and ui_port;" >&2
  echo "      use matching values or stop it with: $CBM daemon stop" >&2
  exit 1
}

start_cbm_proxy() {
  echo "== cbm HTTP proxy 127.0.0.1:$CBM_PROXY_PORT -> 127.0.0.1:$CBM_PORT"
  setsid env \
    PROXY_HOST=127.0.0.1 PROXY_PORT="$CBM_PROXY_PORT" \
    CBM_UPSTREAM_HOST=127.0.0.1 CBM_UPSTREAM_PORT="$CBM_PORT" \
    "$BUN" "$DEV/cbm-http-proxy.ts" > "$OUT/cbm-proxy.log" 2>&1 &
  PROXY_PID=$!
  for _ in $(seq 1 30); do
    if curl -sf --max-time 1 \
      "http://127.0.0.1:$CBM_PROXY_PORT/api/tree?project=$PROJECT" >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  echo "cbm proxy did not become ready; see $OUT/cbm-proxy.log" >&2
  exit 1
}

run_gui() {
  [ -d "$CBM_REPO/graph-ui-svelte/node_modules" ] || {
    echo "missing graph-ui-svelte deps; run (cd ../graph-ui-svelte && bun install)" >&2
    exit 1
  }
  echo "== graph-ui-svelte: bun run gui (code-server)"
  echo "   cbmBaseUrl=http://127.0.0.1:$CBM_PORT project=$PROJECT symbol=$SYMBOL"
  echo "   select source=cbm in the UI; Ctrl-C stops the GUI (and cbm if started here)."
  ( cd "$CBM_REPO/graph-ui-svelte" && exec setsid "$BUN" run gui ) &
  UI_PID=$!
  wait "$UI_PID"
}

run_vite() {
  [ -d "$CBM_REPO/graph-ui-svelte/node_modules" ] || {
    echo "missing graph-ui-svelte deps; run (cd ../graph-ui-svelte && bun install)" >&2
    exit 1
  }
  local host_ip
  host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "== Vite :$UI_PORT (same-origin /api -> 127.0.0.1:$CBM_PROXY_PORT)"
  echo "   open http://${host_ip:-127.0.0.1}:$UI_PORT/ (also 127.0.0.1)"
  echo "   project=$PROJECT symbol=$SYMBOL; Ctrl-C stops Vite, proxy, and cbm if started here."
  # Empty VITE_CBM_BASE means "use location.origin"; Vite's /api proxy then
  # forwards to cbm-http-proxy, which rewrites Host and drops Origin for cbm.
  ( cd "$CBM_REPO/graph-ui-svelte" && exec setsid env \
      CBM_HTTP="http://127.0.0.1:$CBM_PROXY_PORT" \
      VITE_CBM_BASE="${VITE_CBM_BASE-}" \
      VITE_SOURCE="${VITE_SOURCE:-cbm}" \
      VITE_PROJECT="${VITE_PROJECT:-$PROJECT}" \
      VITE_SYMBOL="${VITE_SYMBOL:-$SYMBOL}" \
      "$BUN" run dev -- --host 0.0.0.0 --port "$UI_PORT" ) &
  UI_PID=$!
  wait "$UI_PID"
}

case "$MODE" in
  gui)
    prepare_data
    start_cbm
    run_gui
    ;;
  vite)
    prepare_data
    start_cbm
    start_cbm_proxy
    run_vite
    ;;
esac
