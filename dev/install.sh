#!/usr/bin/env bash
# 只安装 codebase-memory-mcp；其他对照工具已移除。
set -euo pipefail

DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBM_REPO="$(cd "$DEV/.." && pwd)"
RULES="$(cd "$CBM_REPO/.." && pwd)"
BUN="${BUN:-$HOME/.bun/bin/bun}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need node
[ -x "$BUN" ] || { echo "missing bun: $BUN" >&2; exit 1; }

echo "== codebase-memory-mcp 0.12.1 runtime"
mkdir -p "$RULES/cbm-runtime"
if [ ! -f "$RULES/cbm-runtime/package.json" ]; then
  printf '{"name":"peer-cbm","private":true}\n' > "$RULES/cbm-runtime/package.json"
fi
builtin cd "$RULES/cbm-runtime"
"$BUN" add codebase-memory-mcp@0.12.1
"$BUN" pm trust codebase-memory-mcp || true
"$BUN" pm untrusted || true
builtin cd "$DEV"

echo "done. SCIP indexer 在 ../../scip-typescript；当前闭环见 run.sh（--setup 也会装 writer 依赖）"
