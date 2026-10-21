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

The module-level constructor `Comp.svelte -> UserRepo` is scored separately:
its source is the Svelte module, not a callable.

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
| SCIP writer | 11 | 1 | 0 | 91.7% | 100.0% | 95.7% |

cbm misses exactly the cases the gate cares about:

- `useAlias -> UserRepo` and `useAlias -> get`: path alias + barrel
  re-export (`RepoAlias`), including constructor/method resolution.
- `go -> get`: Svelte `<script lang="ts">` is parsed as TS grammar, but
  `cbm_run_ts_lsp` does not run on the embedded block, so the receiver type is
  unavailable.

SCIP covers all 11 function calls. Its one function-level FP is `go -> go`:
the top-level reactive statement `$: name = go()` is attributed to `go`
instead of the module. It also emits five module-level CALLS from
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

Before a global call graph consumes SCIP output, fix the writer:

1. Emit `CALLS` only for actual call expressions; skip import/export/extends
   occurrences (the five module FPs above).
2. Attribute top-level calls to the Module node (or a synthetic module
   function), not to the last enclosing named function (`go -> go`).
3. Keep the existing `enclosing_range` fix; it is why `useHof -> helper` is
   now correct (the older report's 11/12 no longer applies).
