# cbm/dev

当前最小可用闭环（只走这一条）：

```text
dev/fixtures/callgraph-ts-hard
  -> scip-typescript (.scip)
  -> tools/scip-cbm-writer (cbm schema v3 SQLite)
  -> cbm HTTP (127.0.0.1:<ui_port>，默认 9749)
  -> graph-ui-svelte (bun run gui 主路径 / bun run dev 独立 Vite 次路径)
```

cbm 运行时仍在 `../../cbm-runtime/`（codebase-memory-mcp 0.12.1，npm 安装，不入库）。
`graph-ui-svelte/` 和 `tools/scip-cbm-writer/` 是内部目录，不在 `dev/` 里改。

## 快速开始

```bash
cd rules/cbm/dev

./run.sh --setup   # 首次：装 cbm runtime + writer 依赖（会联网，本次未执行）
./run.sh           # 建索引、启 cbm，然后 (cd ../graph-ui-svelte && bun run gui)
./run.sh --vite    # 建索引、启 cbm，然后 bun run dev
```

前置：

- `../scip-typescript/dist/src/main.js` 已构建（或用 `SCIP_INDEXER=...` 指定）
- `node` 可用；`bun` 可用（默认 `~/.bun/bin/bun`，可用 `BUN=...` 覆盖）
- `gui` 模式需要 `code-server` 在 `PATH`
- `--vite` 模式要求 `graph-ui-svelte/node_modules` 已安装

## run.sh

| 模式 | 行为 |
|---|---|
| `./run.sh` / `./run.sh gui` | 硬 fixture → SCIP → writer → cbm HTTP → `bun run gui` |
| `./run.sh --vite` | 同样的数据步骤 → cbm HTTP → `bun run dev` |
| `./run.sh --setup` | 调 `install.sh` 装 cbm runtime，再装 `tools/scip-cbm-writer` 依赖 |

默认产物在 `/tmp/code-graph-demo/`：

```text
hard.scip
index.ext.jsonl
cbm.log
cbm-proxy.log   # 仅 --vite
```

SQLite DB 默认写进 cbm 的缓存目录（`~/.cache/codebase-memory-mcp/fixture-hard-scip.db`），
这样脚本可以直接复用已经在跑的 cbm daemon。

沿用 `run-demo.sh` 的环境变量名；默认缓存改到 cbm 默认目录。常用覆盖项：

| 变量 | 默认 | 用途 |
|---|---|---|
| `CBM_DEV_OUT` / `DEMO_OUT` | `/tmp/code-graph-demo` | 产物目录；删掉或换目录可重建 `.scip` |
| `CBM_CACHE_DIR` | `~/.cache/codebase-memory-mcp` | writer 与 cbm 共用的缓存目录 |
| `CBM_PROJECT` / `DEMO_PROJECT` | `fixture-hard-scip` | cbm project 名 |
| `CBM_PORT` | cbm 配置的 `ui_port`（回退 `9749`） | cbm HTTP 端口（只绑 loopback） |
| `CBM_PROXY_PORT` | `9750` | 仅 `--vite`：给 Vite `/api` 代理用的本地 cbm 代理 |
| `UI_PORT` | `5173` | 仅 `--vite`：Vite 端口 |
| `CBM_SYMBOL` | `$CBM_PROJECT.src.features.useAlias` | `--vite` 初始 symbol |
| `SCIP_INDEXER` | `../scip-typescript/dist/src/main.js` | SCIP indexer 入口 |

脚本用 `set -euo pipefail`；cbm / 代理 / UI 都以独立进程组启动，`trap` 在退出或 Ctrl-C 时清理。

注意：已经在跑的 cbm daemon 会固定 `CBM_CACHE_DIR` 和 `ui_port`。脚本默认读取
`codebase-memory-mcp config get ui_port` 并使用 cbm 默认缓存，所以能直接接上现有
daemon；如果要换缓存或端口，先 `codebase-memory-mcp daemon stop`，或同时把
`CBM_CACHE_DIR`/`CBM_PORT` 设成 daemon 正在使用的值。

## 主路径：graph-ui-svelte + code-server

`run.sh` 打印 code-server URL 后，在 GUI 里：

- Source：`cbm`
- cbmBaseUrl：`http://127.0.0.1:<CBM_PORT>`（默认取 cbm 配置的 `ui_port`；常见 9749/9751）
- Project：`fixture-hard-scip`
- Symbol：`fixture-hard-scip.src.features.useAlias`

`bun run gui` 是 `gui:private` 的别名（loopback + `AUTH=none`）。LAN 用
`bun run gui:public`（密码认证）。注意 cbm 只接受 loopback 同源请求；远程浏览器
不能直接访问 cbm 的 loopback 端口，需要 code-server 的 `/proxy/<port>/` 或一个会改写
`Host`/`Origin` 的反向代理。`cbm-http-proxy.ts` 就是这种通用代理，不限于 React。

## 次路径：standalone Vite

`./run.sh --vite` 让浏览器只访问 Vite（默认 `0.0.0.0:5173`）：

```text
browser -> Vite :5173 /api
        -> cbm-http-proxy :9750  (rewrite Host, drop Origin)
        -> cbm :<ui_port>
```

脚本设置 `VITE_CBM_BASE=`（空字符串），app 因此使用 `location.origin`；Vite 的
`/api` 代理目标由 `CBM_HTTP` 指向本地 cbm 代理。不要直接把 `VITE_CBM_BASE` 指到
cbm：cbm 会拒绝来自 `:5173` 的外来 `Origin`。如果以后 `graph-ui-svelte/vite.config.ts`
自己改写 `Origin`，这层代理可以去掉。

## 历史部分

这些保留下来是为了旧文档/对照，不是当前入口：

| 路径 | 说明 |
|---|---|
| `run-demo.sh` | 旧的 A0/B0 demo：`.scip` → writer → cbm HTTP → Svelte UI + cbm 内嵌 React UI 代理 |
| `cbm-http-proxy.ts` | 通用 cbm HTTP/WebSocket 代理（不限于 React UI） |
| `install.sh` | 只装 cbm runtime；现在由 `run.sh --setup` 调用 |
| `a05/README.md`, `a05/evaluate.py` | A0.5 cbm vs SCIP 对照评测 |
| `fixtures/callgraph-ts` | 早期基础 fixture；外部历史文档仍引用 |
| `fixtures/callgraph-ts-hard` | 当前硬 fixture；`tools/scip-cbm-writer/README.md` 也引用 |

已移除旧的 shell 最小复现脚本和 Python 探针；两者由
`tools/scip-cbm-writer` + `run.sh` 取代（Python 探针只用于最早证明 cbm schema 可写）。
对照结论仍在外部的 `../../out/callgraph-tooling-comparison.md`。
