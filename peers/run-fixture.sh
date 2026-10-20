#!/usr/bin/env bash
# 最小复现：cbm 索引硬 fixture；SCIP 索引 + 探针写 cbm 兼容 DB。
set -euo pipefail

PEERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBM_REPO="$(cd "$PEERS/.." && pwd)"
RULES="$(cd "$CBM_REPO/.." && pwd)"
FIX="$PEERS/fixtures/callgraph-ts-hard"
OUT="$PEERS/out"
SCIP_PRINT="${SCIP_PRINT:-$HOME/tools/scip/scip}"
BUN="${BUN:-$HOME/.bun/bin/bun}"
CBM="$RULES/cbm-runtime/node_modules/.bin/codebase-memory-mcp"

mkdir -p "$OUT/scip-hard"

run() {
  local label="$1"; shift
  printf '\n== %s\n' "$label" >&2
  local t0=$SECONDS
  "$@"
  printf '%s\n' "-- $label: $((SECONDS - t0))s" >&2
}

# cbm 自己索引（对照基线）
run cbm-index "$CBM" cli --json index_repository \
  --repo-path "$FIX" --name fixture-hard --persistence false

run cbm-calls "$CBM" cli --json query_graph --project fixture-hard \
  --query "MATCH (a)-[r:CALLS]->(b) RETURN a.name AS a, a.file AS af, b.name AS b, b.file AS bf, r.strategy AS s"

# SCIP：fork indexer -> .scip -> 探针写 cbm schema
run scip-index node "$RULES/scip-typescript/dist/src/main.js" index \
  --cwd "$FIX" --output "$OUT/scip-hard/hard.scip"

run scip-print "$SCIP_PRINT" print --json "$OUT/scip-hard/hard.scip" \
  > "$OUT/scip-hard/hard.json"

run scip-probe python3 "$PEERS/scip-cbm-probe.py" \
  "$OUT/scip-hard/hard.json" scip-probe-hard "$FIX"

run scip-trace "$CBM" cli --json trace_path --function-name useAlias \
  --project scip-probe-hard --direction outbound --depth 1 --format json

printf '\n完成。产物: %s\n' "$OUT"
