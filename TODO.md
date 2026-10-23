# code navigator — 交接文档

> 更新时间：2026-10-21  
> 工作区：`/home/n/document/code/gpen/gpen-js`  
> 主计划：`rules/tmp/TODO.md`（本地 ignored，历史计划）  
> 当前 GUI 说明：`rules/cbm/graph-ui-svelte/README.md`  
> 本文件：当前实现、运行方式、未提交状态、下一步。

---

## 0. 一句话

**SCIP 索引 → cbm SQLite → Svelte `code-graph` GUI / TUI / Fresh 跳转** 的主链路已经跑通；当前剩下的是**真实 Fresh 端到端验证、提交整理、A2 `/api/source`（可选）**。VSCode 已明确搁置。

---

## 1. 当前状态

| 模块 | 状态 | 说明 |
|---|---|---|
| A0 `.scip` → cbm writer | ✅ 完成 | TS + Bun，直接读 protobuf，写 cbm schema v3 |
| A0.5 SCIP 去留评估 | ✅ 完成 | TS/JS/Svelte 用 SCIP；cbm 管其余 ~160 语言 |
| A0.6 CALLS 清理 | ✅ 完成 | 只发真实调用；顶层调用归 Module；0 FP |
| B0 `code-graph` 骨架 | ✅ 完成 | Svelte 5 + Vite + `GraphSource` |
| B1 跳转协议 v2 | ✅ 完成 | JSON-RPC 2.0 + TypeSpec → JSON Schema + Ajv |
| B2 局部图 | ✅ 完成 | D3 SVG + orchgraph 字符画双渲染器 |
| B3 Fresh adapter | ✅ 代码完成，⚠️ 真实会话待验 | `spawnProcess` 调 `jump-client` |
| B3 VSCode adapter | ⏸ 搁置 | 保留旧 v1 代码，不测试、不迁移 |
| B4 TUI / Fresh 插件 | ✅ 代码完成，⚠️ 真实 Fresh 待验 | 虚拟缓冲区 + 点击 + openFile |
| A2 `/api/source` | ⬜ 未做（可选） | GUI 当前不依赖 |

### 验证数字

A0.5/A0.6 hard fixture（11 个函数级 ground truth）：

```text
cbm：   8/11   precision 100%   recall 72.7%
SCIP： 11/11   precision 100%   recall 100%
module：2/2，0 FP
```

writer 实际产出：

```text
hard fixture：7 docs / 48 nodes / 60 edges / 13 calls
gpen-js：     163 docs / 6254 nodes / 8634 edges / 2380 CALLS
```

---

## 2. 仓库与目录

```text
gpen-js/
└── rules/
    ├── cbm/                          # submodule → AClon314/codebase-memory-mcp，main @6fd366d
    │   ├── graph-ui/                 # 原 React UI（稳定，未替换）
    │   ├── graph-ui-svelte/           # submodule → AClon314/code-graph，main @c1d8b89
    │   │   ├── src/                  # Svelte GUI
    │   │   ├── tui/                  # orchgraph TUI frame
    │   │   ├── fresh-plugin/          # Fresh QuickJS 插件
    │   │   ├── extensions/vscode/     # 已搁置的旧 adapter
    │   │   ├── tools/                 # jump-bridge / jump-client
    │   │   └── contracts/             # TypeSpec + 生成 schema
    │   ├── tools/scip-cbm-writer/     # submodule，main @a128746
    │   ├── dev/                       # a05 harness / fixtures / run scripts
    │   └── TODO-cdnFont.md            # 独立未开工：React graph-ui CDN 字体方案
    ├── cbm-runtime/                  # npm 0.12.1 运行时（gitignored）
    ├── out/                          # 工具/渲染对比报告
    ├── scip-typescript/              # submodule（gpen fork）
    ├── scip-symbol-graph/            # submodule
    ├── jelly/                         # submodule
    └── tmp/TODO.md                   # 历史计划（ignored）
```

**命名**：新仓库/构建产物用通用名 `code-graph`；`gpen` 只作为测试语料名。cbm 内的挂载目录仍叫 `graph-ui-svelte/`。

---

## 3. 架构

```text
scip-typescript fork
        │ index.scip
        ▼
cbm/tools/scip-cbm-writer          (TS + Bun)
        │ cbm SQLite schema v3
        ▼
cbm runtime (MCP / HTTP)
        ├── cbm/graph-ui (React)      其他 workspace / Galaxy
        └── cbm/graph-ui-svelte       code-graph
               ├── D3 + ELK           局部 SVG 图 / Export SVG
               └── orchgraph          字符画 <pre> / Copy
```

### 跳转链路

```text
GUI / TUI
   │ JumpTarget { project, path, line, column?, symbol? }
   ▼
JumpClient ──JSON-RPC POST /rpc──> jump-bridge
                                   │ 队列 + TTL + 去重 + 路径校验
                                   ▼
Fresh plugin ──spawnProcess──> tools/jump-client.ts
                                   │ long-poll /rpc
                                   ▼
                             editor.openFile(path, line, column)
```

bridge 是**传输/队列层**，不是 IDE 抽象层；抽象是 `JumpTarget` 契约 + 每个 IDE adapter。

---

## 4. 已完成内容

### A0 writer（`rules/cbm/tools/scip-cbm-writer/`）

- 直接读 `.scip` protobuf，不跑 `scip print --json`
- 写 cbm schema v3：节点/边、`CONTAINS_*`、`CALLS`、`file_path/start_line/end_line`
- sidecar `index.ext.jsonl` 只放扩展字段
- 回归测试覆盖：
  - 只对 `SyntaxKind.IdentifierFunction` 发 `CALLS`
  - 跳过 `Definition` / `Import`
  - `enclosing_range` 决定 caller
  - 顶层调用归 Module，不继承上一个函数
- 测试：`bun test`（writer 目录）2 pass / 74 expect

### A0.5 / A0.6 结论

- **SCIP 接管 TS/JS/Svelte**，cbm 继续管其余语言
- cbm 漏召回主要在 path alias、barrel、Svelte embedded TS
- writer 保持外部 submodule，不深 fork cbm C 核心

### B1 JSON-RPC v2

- `POST /rpc`，方法：
  - `jump.open`
  - `jump.next`
  - `jump.ack`
- `GET /health` 仅健康检查
- 标准错误：
  - `-32700` parse
  - `-32600` invalid request
  - `-32601` method not found
  - `-32602` invalid params（Ajv `instancePath` / `message`）
  - `-32603` internal
- `contracts/code-nav.tsp` 唯一来源
  - `@typespec/json-schema` 生成 Draft 2020-12 bundle
  - `contracts/generated/code-nav.schema.json`
- bridge：
  - 队列 TTL 30s
  - 相同 target 去重
  - repo-relative 路径校验（拒绝绝对路径、`..`、盘符）
  - 默认 `127.0.0.1:9752`
  - `CODE_NAV_BIND=0.0.0.0` + `CODE_NAV_TOKEN` 才允许 LAN
- `JumpClient`：JSON-RPC envelope、错误转换、long-poll
- `tools/jump-client.ts`：
  - Fresh 专用 CLI
  - `next --client fresh --wait 25000 --out ...`
  - token 从 `CODE_NAV_TOKEN` 或 `CODE_NAV_TOKEN_FILE` 读取，**不进 argv**
  - 原子写结果

### B2 GUI

- `GraphSource` 契约：`projects / tree / symbol / trace / impact / source / search`
- `CbmHttpSource` + `MockSource`
- file tree + symbol 列表 + 1–3 跳 callers/callees
- URL 状态同步：

```text
?source=&project=&symbol=&file=&line=&renderer=&depth=&direction=
```

- 两种渲染器：
  - **D3**：SVG、zoom/pan、`Export SVG`
  - **orchgraph**：与 TUI 相同的 box-drawing 字符画，`<pre>` 直接显示，`Copy` 复制纯文本
- orchgraph 的节点点击/双击/键盘事件通过透明 hitbox 覆盖层实现
- 搜索命中、选中状态用 hitbox 边框/底色显示
- 字符画字体：

```css
--font-code:
  "UbuntuMono Nerd Font",
  "Victor Mono",
  "Noto Sans Mono",
  "DejaVu Sans Mono",
  "Adwaita Mono",
  monospace;
```

- `line-height: 1`；实测 2 个英文字符 = 1 个中文字符
- 浏览器版 orchgraph 不能直接 import `orchgraph` 根入口（含 `node:module` / `node:worker_threads`），所以：
  - `src/lib/graph/terminal.ts` 是 orchgraph 0.2.4 的**浏览器安全窄复制**
  - 布局仍用共享 ELK（`src/lib/graph/layout.ts` 的 `createElk`）
  - 升级 orchgraph 时要同步这个文件

### B3 Fresh

`fresh-plugin/code-nav.ts`：

- 不再用 `editor.httpFetch`（该 API 只支持 GET 下载）
- `editor.spawnProcess(BUN, [jump-client.ts, "next", "--client", "fresh", ...])`
- 读取临时结果，去重后 `editor.openFile(path, line, column)`
- 虚拟缓冲区、点击命中、overlay、面板显示
- `bun build --target=browser` 通过（无 import，QuickJS 可加载）
- fake editor harness 验证：打开文件、去重、关闭、点击 overlay

**未完成**：真实 Fresh 0.5.4 会话端到端验证。

### B4 TUI

- `tui/frame.ts`：`GraphViewData → orchgraph → Frame`
- `tui/render.ts`：fixture / cbm 数据 → frame JSON
- orchgraph 输出 ANSI，frame 解析成 `{t, fg, bold}` runs
- Fresh 插件把 frame 画进虚拟缓冲区
- `tmp/fresh` 原型已归档到 `tmp/archive/fresh-prototype/`（ignored）

### B3 VSCode（搁置）

- `extensions/vscode/` 保留，但仍是旧 v1 REST 轮询
- **不测试、不迁移 JSON-RPC、不加固、不纳入测试矩阵**
- 恢复前不要改；`extensions/vscode/README.md` 顶部已标 SHELVED

---

## 5. 运行方式

### GUI 本地

```bash
cd rules/cbm/graph-ui-svelte
bun install
bun run contracts:compile   # 可选；build 会自动跑
bun run dev                 # Vite，默认 0.0.0.0:5173
```

Mock 模式直接访问：

```text
http://127.0.0.1:5173/?source=mock&symbol=demo.src.main.main&renderer=orchgraph
```

切 D3：

```text
...&renderer=d3
```

### 真实 cbm 图

```bash
# 1. 生成 cbm DB
(cd rules/cbm/tools/scip-cbm-writer && bun run src/cli.ts /path/to/index.scip \
  --project fixture-hard-scip \
  --root ../dev/fixtures/callgraph-ts-hard \
  --cache-dir /tmp/cbm-cache-scip)

# 2. 启动 cbm HTTP（保持 stdin 打开）
CBM_CACHE_DIR=/tmp/cbm-cache-scip \
  rules/cbm-runtime/node_modules/.bin/codebase-memory-mcp \
  --ui=true --port=9751

# 3. Vite 代理
CBM_HTTP=http://127.0.0.1:9751 bun run --cwd rules/cbm/graph-ui-svelte dev
```

GUI 选 `cbm HTTP`，project 填 `fixture-hard-scip`。

> cbm daemon 对自定义 `CBM_CACHE_DIR` 有账户级 cache 冲突：报 “active account daemon uses a different cache directory” 时，改用默认 cache + 新 project 名。

### 跳转 bridge

```bash
cd rules/cbm/graph-ui-svelte
bun run jump:bridge
# 默认 127.0.0.1:9752

# LAN / Tailscale
CODE_NAV_BIND=0.0.0.0 CODE_NAV_TOKEN=... bun run jump:bridge
```

### TUI fixture

```bash
cd rules/cbm/graph-ui-svelte
bun run tui/render.ts --graph tui/fixture-graph.json --out /tmp/frame.json
```

### 校验

```bash
cd rules/cbm/graph-ui-svelte
bun test          # 20 pass
bun run check     # svelte-check 0/0
bun run build     # success（bundle ~1.57 MB，chunk warning 未处理）
```

---

## 6. 当前 git / 工作区状态

> 截至本文写作时，**很多改动尚未提交**。

| 仓库 | HEAD | 状态 |
|---|---|---|
| 父仓库 `gpen-js` | `67334cc` | `rules/cbm` 子模块指针 modified；本地领先 origin/main 9 |
| `rules/cbm` | `6fd366d` | `m graph-ui-svelte`；`?? TODO-cdnFont.md`；本地领先 1 |
| `rules/cbm/graph-ui-svelte` | `c1d8b89`（jj main），工作副本 `f241892` | 大量 modified / untracked，**未提交** |
| `tools/scip-cbm-writer` | `a128746` | clean |
| `rules/scip-typescript` | `4cd2db1` | fork |
| `rules/scip-symbol-graph` | `6f12675` | clean |
| `rules/jelly` | `08af674` | clean |

`code-graph` 当前未提交内容大致包括：

- JSON-RPC v2 / TypeSpec / Ajv
- jump-client / Fresh 插件切换
- D3 + orchgraph 字符画双渲染器
- orchgraph 字体栈、Copy、URL 同步
- `test/jump-rpc.test.ts`、`test/orchgraph.test.ts`、`test/terminal.test.ts`

**提交前必须先确认 `graph-ui-svelte` 的改动范围，再更新 cbm 子模块指针和父仓库指针。**

`TODO-cdnFont.md` 是独立的、尚未开工的 React graph-ui CDN 字体方案，不要误删；它不属于当前 `code-graph` 任务。

---

## 7. 已知限制 / 风险

1. **真实 Fresh 未验证**
   - 插件已用 fake editor harness 验证
   - 但 `/home/n/.cargo/bin/fresh` 0.5.4 的真实会话、QuickJS 加载、`spawnProcess` 实际路径尚未端到端跑过

2. **VSCode 不可用**
   - `extensions/vscode/` 仍是 v1 REST
   - 当前没有 token / JSON-RPC / 路径安全更新
   - 不要把它当作可用 adapter

3. **orchgraph 浏览器渲染是窄复制**
   - `src/lib/graph/terminal.ts` 与 orchgraph 0.2.4 的 `renderCanvas` 同步
   - 升级 orchgraph 后必须重跑 `test/terminal.test.ts`，并对比 TUI 输出

4. **字符画没有 ANSI 颜色**
   - 当前 web 用 `renderTerminalCanvas({ color: false })`
   - 状态 marker（`○/●/✓/✕`）保留；TUI 的黄色/绿色状态色未在 web 还原
   - 如果需要，可加 ANSI → `<span>` 渲染；Copy 仍复制纯文本

5. **Copy 依赖浏览器权限**
   - 使用 `navigator.clipboard.writeText` + `execCommand` fallback
   - headless/embedded 环境会拒绝；真实用户点击通常可用
   - 失败会显示 `Copy failed: ...`

6. **bridge 安全**
   - 默认 loopback；LAN 必须显式 bind + token
   - 路径限制在 repo-relative
   - `jump-client` token 不进 argv，但会继承环境变量或读 token 文件

7. **bundle 体积**
   - `bun run build` 约 1.57 MB（gzip 487 KB）
   - 主要来自 ELK；仍有 Vite chunk warning
   - 未做 code-split

8. **全局图**
   - 当前只做局部 1–3 跳图
   - 全局图继续用 cbm Galaxy；后续按 module 聚合

9. **cbm schema 内部契约**
   - 固定 0.12.1；writer/UI 用 fixture 锁形状
   - 升级 cbm 时要重新跑 writer + a05

10. **`/api/source` 缺失**
    - GUI 当前不做源码预览
    - `source` / `search` 在 cbm 0.12.1 不完整
    - A2 可并行，但不是当前 GUI 阻塞项

---

## 8. 下一步优先级

### P0：提交整理

1. 复核 `graph-ui-svelte` 未提交 diff
2. 跑：

```bash
cd rules/cbm/graph-ui-svelte
bun test
bun run check
bun run build
```

3. 提交 `code-graph`
4. 更新 `rules/cbm` 的 `graph-ui-svelte` 子模块指针
5. 更新父仓库 `rules/cbm` 指针
6. 视需要 push（当前本地领先 origin/main）

### P1：真实 Fresh 端到端

- 用 Fresh 0.5.4 加载 `fresh-plugin/code-nav.ts`
- 验证：
  - 插件加载（无 import）
  - bridge 启动
  - GUI Jump → `jump-client` long-poll → `editor.openFile`
  - 重复 target 去重
  - 非法路径/参数不打开文件

### P2：可选

- A2 `GET /api/source`（MCP `get_code_snippet` 适配）
- orchgraph 字符画 ANSI 颜色
- 大图聚合 / module 级全局图
- bridge 请求去重、TTL、路径规范化继续调优
- VSCode 恢复时再迁移 JSON-RPC（当前不做）

---

## 9. 接手第一小时清单

- [ ] 读本文件 + `graph-ui-svelte/README.md`
- [ ] `git status` 确认未提交改动，不要误覆盖
- [ ] `bun test` / `bun run check` / `bun run build`
- [ ] 启动 `bun run dev`，用 Mock + `renderer=orchgraph` 看字符画
- [ ] 启动 `bun run jump:bridge`，点节点 Jump，确认 bridge `/health`
- [ ] 跑一次 `tui/render.ts --graph tui/fixture-graph.json`
- [ ] 决定是否先提交，再做真实 Fresh 验证
- [ ] 不要动 `extensions/vscode/`

---

## 10. 关键文件索引

| 路径 | 作用 |
|---|---|
| `rules/cbm/graph-ui-svelte/src/App.svelte` | GUI 主界面、URL 同步、Jump、D3/orchgraph 切换 |
| `src/lib/components/GraphView.svelte` | D3 SVG 渲染器 |
| `src/lib/components/OrchgraphView.svelte` | orchgraph 字符画渲染器 + Copy |
| `src/lib/graph/terminal.ts` | 浏览器安全 orchgraph 字符 canvas |
| `src/lib/graph/layout.ts` | 共享 ELK 布局、`createElk` |
| `src/lib/graph/orchgraph.ts` | GraphViewData → orchgraph document/geometry |
| `src/lib/graph/neighborhood.ts` | 1–3 跳 BFS |
| `src/lib/jump/types.ts` | JumpTarget / JSON-RPC 类型 |
| `src/lib/jump/client.ts` | GUI JSON-RPC client |
| `tools/jump-bridge.ts` | JSON-RPC bridge / 队列 / Ajv |
| `tools/jump-client.ts` | Fresh 侧 long-poll CLI |
| `fresh-plugin/code-nav.ts` | Fresh QuickJS 插件 |
| `tui/frame.ts` | orchgraph → ANSI Frame |
| `tui/render.ts` | fixture / cbm → Frame CLI |
| `contracts/code-nav.tsp` | 跳转协议唯一来源 |
| `contracts/generated/code-nav.schema.json` | 生成 schema（不要手改） |
| `rules/cbm/dev/a05/evaluate.py` | SCIP vs cbm 评分 |
| `rules/tmp/TODO.md` | 历史计划（本地 ignored） |
