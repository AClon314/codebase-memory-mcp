# A0.5 — cbm vs SCIP on the hard TS/Svelte fixture

Decision gate for D8: does cbm's native TS/Svelte resolver suffice, or does
the product need SCIP for those languages?

## Fixture and ground truth

Fixture: `../fixtures/callgraph-ts-hard` (7 files, TS + Svelte `<script lang="ts">`).

Function-level ground truth (11 calls, source is a named function/method):

```text
useAlias -> UserRepo, get          useGeneric -> identity
useCond -> load                    useHof -> apply, helper
useOverload -> pick                get -> load
load -> make                       go -> get, helper
```

Module-level calls are scored separately because their source is the Svelte
module, not a callable: `Comp.svelte -> UserRepo` (constructor) and
`Comp.svelte -> go` (top-level reactive statement).

## Reproduce

```bash
FIX="$(cd "$(dirname "$0")/../fixtures/callgraph-ts-hard" && pwd)"
OUT=/tmp/a05
mkdir -p "$OUT/scip-cache"

# cbm-native index (default cache; use a fresh project name)
CBM_CACHE_DIR="${CBM_CACHE_DIR:-$HOME/.cache/codebase-memory-mcp}" \
  ../../../cbm-runtime/node_modules/.bin/codebase-memory-mcp cli --json \
  index_repository --repo-path "$FIX" --name fixture-hard-a05 --persistence true

# SCIP index + writer
node ../../../scip-typescript/dist/src/main.js index \
  --cwd "$FIX" --output "$OUT/hard.scip" --no-progress-bar
( cd ../../tools/scip-cbm-writer && bun run src/cli.ts "$OUT/hard.scip" \
  --project fixture-hard-scip --root "$FIX" --cache-dir "$OUT/scip-cache" )

python3 evaluate.py \
  "$HOME/.cache/codebase-memory-mcp/fixture-hard-a05.db" \
  "$OUT/scip-cache/fixture-hard-scip.db"
```

`evaluate.py` reads only `CALLS` edges and prints function- and module-level
scores separately. It does not hide false positives.

## Result (2026-10-21)

| Tool | Function TP | FP | FN | Precision | Recall | F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| cbm-native | 8 | 0 | 3 | 100.0% | 72.7% | 84.2% |
| SCIP writer | 11 | 0 | 0 | 100.0% | 100.0% | 100.0% |

Module-level edges: cbm `TP=1 FP=1`; SCIP writer `TP=2 FP=0` after A0.6.

cbm misses exactly the cases the gate cares about:

- `useAlias -> UserRepo` and `useAlias -> get`: path alias + barrel
  re-export (`RepoAlias`), including constructor/method resolution.
- `go -> get`: Svelte `<script lang="ts">` is parsed as TS grammar, but
  `cbm_run_ts_lsp` does not run on the embedded block, so the receiver type is
  unavailable.

SCIP covers all 11 function calls. The former `go -> go` FP is fixed: the
top-level reactive statement `$: name = go()` now stays on the module. The
writer also stopped emitting the five module-level CALLS from
import/export/extends occurrences:

```text
Comp.svelte -> helper          import
features.ts -> UserRepo        import
features.ts -> helper          import
lib/barrel.ts -> UserRepo      export
lib/user-repo.ts -> BaseRepo   import
UserRepo -> BaseRepo           extends
```

Those are writer hygiene issues, not semantic misses: SCIP has the right
symbols, but the writer must not turn every reference into `CALLS`.

## A0.6 result

The writer now:

1. Emits `CALLS` only for `SyntaxKind.IdentifierFunction` occurrences; import,
   export and extends references carry no call syntax kind.
2. Uses the definition's `enclosing_range` to bound the fallback caller search;
   a top-level statement no longer inherits the previous function.
3. Re-scores as **function 11/11, 0 FP; module 2/2, 0 FP**.

## Decision

**Use SCIP for TS/JS/Svelte; keep cbm for the other ~160 languages.**

- cbm-native's recall gap is structural: fixing it means running the TS
  resolver on embedded Svelte blocks and extending re-export resolution in the
  C heuristics. That is A1 work, not a configuration change, and it still
  inherits the heuristic boundary.
- SCIP gets the hard semantic edges. The remaining defects are in our writer,
  where they are cheap to fix.
- Keep the writer external for now (D4). Do not deep-fork `src/scip/` until
  incremental indexing or a single-binary product actually requires it.

The writer hygiene work is done (A0.6). A global call graph can now consume
SCIP output without the import/export/extends false positives or the
`go -> go` attribution error.
