# cbm/dev

只保留 **SCIP→cbm 探针** + 两个 fixture；cbm 运行时已移到
[`../../cbm-runtime/`](../../cbm-runtime/)（codebase-memory-mcp 0.12.1）。
tsa / lspgraph / multilspy / ScubaTrace / Source Atlas 已移除；对比结论保留在
[`../../out/callgraph-tooling-comparison.md`](../../out/callgraph-tooling-comparison.md)。

| 路径 | 内容 |
|---|---|
| `scip-cbm-probe.py` | `.scip` → cbm schema v3 SQLite 的可行性探针 |
| `fixtures/callgraph-ts` | 基础 TS/Svelte/Python fixture |
| `fixtures/callgraph-ts-hard` | 类型系统硬 fixture（path alias / 重导出 / 泛型 / Svelte TS） |
| `../../cbm-runtime/` | codebase-memory-mcp 0.12.1 运行时（npm 安装，不入库） |
| `..` | cbm fork 根；`graph-ui-svelte/` 与 `tools/scip-cbm-writer/` 在内部 |
| `install.sh` | 只装 cbm runtime 到 `../../cbm-runtime/` |
| `run-fixture.sh` | cbm + SCIP + 探针的最小复现 |
| `run-demo.sh` | A0/B0 集成 demo：`.scip` → writer → cbm HTTP → Svelte UI + React 代理 |
| `react-ui-proxy.ts` | 把 cbm 的 loopback React UI 暴露到 `0.0.0.0:9749`（Host/Origin 改写） |

```bash
./install.sh
./run-fixture.sh
./run-demo.sh        # A0 + B0 end-to-end; prints Svelte + React URLs
```

前置：`rules/scip-typescript` 已构建；`~/tools/scip/scip` 可用；`PATH` 含 `~/.bun/bin`。
