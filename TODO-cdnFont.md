# TODO: GUI 没有「Maple Mono NF CN」时改用 CDN 版本

状态：**React `graph-ui` 部分未开工**；**GUI-HTML（`graph-ui-svelte`）已落地**，见下方
「实施记录」。本文档其余内容保留为 React 版的交接说明。

> **术语**：本文所有「本机」都指**客户端浏览器所在的机器**，不是服务端。GUI 可以被
> 另一台机器打开（`graph-ui-svelte` 的 Vite 就监听 `0.0.0.0`），所以字体探测必须在
> 浏览器里做，不能去问服务端装了什么字体。

> **实施记录（2026-10-23，GUI-HTML / `graph-ui-svelte`）**：
> - `src/lib/fonts.ts`：客户端 canvas 探测（3 基线 × 2 样本 × 5 度量）；本机有字体时
>   只写 `data-font-maple="system"`，**零网络请求**；没有时才注入
>   `referrerPolicy="no-referrer"` 的 CDN 样式表，`document.fonts.load()` 成功后才写
>   `data-font-maple="cdn"`，失败/超时静默保留本地栈。
> - `src/main.ts` 在 `mount()` 前调用一次；`src/app.css` 把 `"Maple Mono NF CN"` 放到
>   `--font-code` 栈首；`test/fonts.test.ts` 覆盖 system / cdn / 样式表失败 / 空 face /
>   超时 / 重复调用 / 探测抛错。
> - 该 GUI 不嵌入 C 二进制、没有 CSP，所以本文 §2、§5.3、§6 中 `graph-ui`、CSP、
>   `embedded_assets` 的部分不适用。
> - 实测（本机未装 Maple）：1 × `result.css` + 7 × `.woff2`（ASCII + 字符画块；CJK
>   块由标签按需拉取）；伪造本机已装字体后 `zeosevenRequests: []`、
>   `document.fonts.size === 0`。
> - `◐`（U+25D0）不在 CDN 字体覆盖范围内，浏览器会回落到比例字体，宽度不是 1 个
>   字符格；GUI 静态视图改为 `●`（Maple 有、宽度恰好 1 格）。

目标仓库：`gpen-js/rules/cbm`（codebase-memory-mcp 子模块）
影响面（React 版）：`graph-ui`（含被 `scripts/embed-frontend.sh` 塞进二进制的产物）+ `src/ui/http_server.h` 的 CSP + 一个 C 测试

---

## 1. 目标

1. `graph-ui` 的代码/终端字体栈 `--atlas-mono` 首选 `"Maple Mono NF CN"`。
2. **本机已经装了该字体时，一个网络请求都不发**（现状等价，不引入回归）。
3. 本机没有时才从 ZeoSeven CDN 加载；加载失败/超时静默回落到现在这套 `ui-monospace, …` 栈。
4. 离线、CSP、`StrictMode` 双调用这些边界都要照顾到（见 §5、§6）。

---

## 2. 现状：要改的四个位置

| 位置 | 现状 | 要做什么 |
|---|---|---|
| `graph-ui/src/styles/tokens.css:43` | `--atlas-mono: ui-monospace, SFMono-Regular, "SF Mono", "JetBrains Mono", Menlo, Consolas, "Liberation Mono", monospace;` | 栈首插入 `"Maple Mono NF CN",`（token 是唯一入口，6 个 CSS 文件 15 处读它，不用逐个改） |
| `graph-ui/src/main.tsx` | 只 import 三个 css + `installUiLog()`，然后 `createRoot` | 加一行 `installFontFallback()`（非阻塞，不 await 渲染） |
| `src/ui/http_server.h:26` | `style-src 'self' 'unsafe-inline'; font-src 'self' data:;` | **会拦掉 CDN**：两个指令各加 `https://fontsapi.zeoseven.com` |
| `tests/test_httpd.c:1840` `ui_csp_connect_src_has_explicit_download_hosts` | `ASSERT_EQ(secure_hosts, 2)`，且断言 CSP 里没有 `*` | 改 CSP 后 `https://` 出现次数变 4（style-src + font-src 各一个），断言同步更新；新增一条「字体 CDN 只在 font-src/style-src，不进 script-src」的断言更好 |

另：`scripts/embed-frontend.sh` 已支持 `*.woff2 → font/woff2`，如果走 §7 的自托管方案不用改它。

补充事实：`src/ui/httpd.c:248` 把监听地址写死成 `127.0.0.1`（`htonl(0x7F000001)`），所以 GUI 一定是 `http://127.0.0.1:PORT` 打开的 —— **这正好踩中 CDN 的防盗链规则**（见 §4.2），`referrerPolicy="no-referrer"` 是硬要求，不是可选优化。

---

## 3. CDN 是什么

`https://fonts.zeoseven.com/items/442/` = **Maple Mono NF CN**（圆角等宽 + 连字 + Nerd Font 图标 + 中日韩字形，SIL OFL 1.1）。

- 样式表：`https://fontsapi.zeoseven.com/442/main/result.css`（151 KB 原始 / **48.3 KB gzip**，191 条 `@font-face`）
- 用 `cn-font-split` 切成 **191 个 woff2 分块**，每块带自己的 `unicode-range`，浏览器只下载页面真的用到的字形
- 分块头：`cache-control: public, immutable, max-age=31536000`、`access-control-allow-origin: *`
- 全部分块合计 **10.23 MB**（单块 5.2～122 KB，中位 55 KB）
- 只有 `main/` 一个端点有效（`webfont/`、`lite/` 都是 404）

### 实测客户端下载量（Chrome 157 + CDP `encodedDataLength`，含 gzip）

| 场景 | 分块 | 字体字节 | +样式表 | 合计 |
|---|---|---|---|---|
| 纯英文 + 数字 | 2 | 61 KB | 48.3 KB | **0.11 MB** |
| gui 里实际会出现的字符（ASCII + 少量中文标签） | ~3–8 | 100–300 KB | 48.3 KB | **0.15–0.35 MB** |
| 100 个常用汉字 + 英文 | 7 | 246 KB | 48.3 KB | 0.29 MB |
| 300 个不重复汉字 | 18 | 1.05 MB | 48.3 KB | 1.10 MB |
| 全部字形 | 191 | 10.23 MB | 48.3 KB | 10.3 MB |

**关键结论**：不存在「一上来就 10MB」；成本由页面里出现的**不重复字数**决定，几何级数增长的是生僻字/繁体/制表符号。GUI 这种以 ASCII 代码为主的界面基本落在 0.1～0.3 MB。

---

## 4. 两个必须知道的坑

### 4.1 `204 No Content` 是最阴的失败形态

加载失败时控制台**不报错**、网络面板没有失败标记、请求"成功"了，只是内容为空 → `document.fonts.size === 0`，字体静默回落。排查时先看状态码是不是 204。

### 4.2 防盗链：Referer 是 IP 字面量就回 204

用 curl 做的头矩阵（每个组合重复 2–3 次，结果稳定）：

```
-A <正常UA> -e http://127.0.0.1:5181/     → 204（0 字节）
-A <正常UA> -e http://localhost:5181/     → 200
-A <正常UA> -e http://example.com:5181/   → 200
-A <正常UA> -e https://github.com/        → 200
-e http://8.8.8.8/ / http://[::1] / http://192.168.x.x → 204
-H 'User-Agent:'（空 UA）                  → 204
无 Referer 头                              → 200
```

所以：**IP 字面量 Referer 或空 UA 一律 204**。GUI 跑在 `127.0.0.1`，不处理就是必踩。

```ts
const link = document.createElement('link');
link.rel = 'stylesheet';
link.href = 'https://fontsapi.zeoseven.com/442/main/result.css';
link.referrerPolicy = 'no-referrer'; // ← 硬要求
```

想写成 index.html 里的静态 `<link>` 就得带 `referrerpolicy="no-referrer"`，或页面加 `<meta name="referrer" content="no-referrer">`（后者影响全站请求，副作用更大，不推荐）。

### 4.3 204 还会被缓存，故障自我延长

`cache-control: public, max-age=600` + 204 是可缓存组合：一次踩中之后，**同一个 profile 里 10 分钟内所有请求都拿到缓存的空响应**，改代码、加 `no-referrer` 全都没用，非常容易被误判成「网络/代理问题」。排查时用新 profile（新 `agent-browser --session`）或加随机 query 绕过缓存复测。

（我自己在 fontTest 项目里就被这个坑骗过一轮：先得出"某个 Chrome 实例拿不到任何跨域子资源"的错误结论，换新 session 立刻正常。）

---

## 5. 实现步骤

### 5.1 探测本机是否有这个族

用 canvas 度量对比（`fontTest/src/lib/fonts.js` 的 `detectFamily()` 可直接抄，30 行）：

```ts
// 字体不存在时会整段回落到基线，全部度量必然与基线相同
const METRICS = ['width', 'actualBoundingBoxAscent', 'actualBoundingBoxDescent',
                 'fontBoundingBoxAscent', 'fontBoundingBoxDescent'];
function exists(family: string, baseline = 'monospace'): boolean {
  const ctx = document.createElement('canvas').getContext('2d')!;
  const probe = (font: string) => {
    ctx.font = font;
    const m = ctx.measureText('mmmmmmmmmmlliWWW@0O1Il意中文字体');
    return METRICS.map((k) => (m as any)[k] as number);
  };
  const withFamily = probe(`72px ${JSON.stringify(family)}, ${baseline}`);
  const withBaseline = probe(`72px ${baseline}`);
  return withFamily.some((v, i) => Math.abs(v - withBaseline[i]) > 0.05);
}
```

**不要用 `document.fonts.check('13px "Maple Mono NF CN"')` 判断**：对系统已安装字体它经常直接返回 `true`（找不到匹配 face 也算"满足"），会误判成"有"，从而永远不加载 CDN。

（`window.queryLocalFonts()` 也能查，但仅 Chromium + 需用户授权，不适合做启动期判断。）

### 5.2 注入与等待

```ts
let started = false;
export function installFontFallback() {
  if (started) return;              // React StrictMode 会重复执行 module 级 effect
  started = true;
  if (exists('Maple Mono NF CN')) return;   // 本机有 → 零网络请求
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = CDN_HREF;
  link.referrerPolicy = 'no-referrer';
  link.onload = async () => {
    try {
      // 关键：先按当前界面用到的字符把分块拉下来，
      // 否则紧接着的 canvas 探测 / 首屏测量量到的还是回退字体
      await document.fonts.load('13px "Maple Mono NF CN"', SAMPLE);
      document.documentElement.dataset.fontMaple = 'cdn';
    } catch { /* 静默：回退字体栈继续工作 */ }
  };
  link.onerror = () => { /* 断网/被拦：静默回落，记一条 ui-log */ };
  document.head.appendChild(link);
  setTimeout(() => { if (!document.documentElement.dataset.fontMaple) { /* 3s 超时也记一条 */ } }, 3000);
}
```

要点：

- **`--atlas-mono` 无条件把 Maple 放最前**即可。字体不可用时浏览器自然回落到下一个名字，不会白屏、不会报错 —— 所以 CSS 侧不需要任何条件分支，只有"要不要发网络请求"需要判断。
- `installFontFallback()` 在 `createRoot(...).render(...)` **之前**同步调用，但它自己不做任何 `await`，不阻塞首屏。
- 字体到位后会有一次重排（monospace 度量不同，行高/宽度都会变）。`result.css` 里是 `font-display: swap`，可接受；若要彻底消除抖动，可以把 `SAMPLE` 缩到 ASCII 那几块（代价仍是 48 KB 的样式表）。
- 样式表 191 条 `@font-face` 的解析本身很快，但它是**阻塞渲染**的外部样式表（浏览器要在 CSS 到位后才知道要不要重排）。如果 GUI 对首屏时间敏感，改成「先渲染 → `requestIdleCallback` 再注入」更稳（此时首屏用回退字体，字体到了再 swap）。

### 5.3 CSP

```c
"style-src 'self' 'unsafe-inline' https://fontsapi.zeoseven.com; font-src 'self' data: https://fontsapi.zeoseven.com; "
```

- 只放行 host，不要用 `*`、不要给 `script-src` 加任何东西（`tests/test_httpd.c:1840` 会抓）。
- `connect-src` 不需要改（`<link>` 与字体请求不走 fetch/XHR，但这取决于浏览器实现，稳妥的话也可以不放 —— 实测 Chrome 只需 `style-src` + `font-src`）。
- 页面是 `http://127.0.0.1`，加载 `https://` 资源不算混合内容问题。

---

## 6. 验收标准

| 用例 | 期望 |
|---|---|
| 装了 Maple 的机器启动 GUI | DevTools 里 **0** 个 `zeoseven` 请求；`document.fonts.size === 0` 也正常（系统字体不入 FontFaceSet） |
| 没装 Maple | 1 × `result.css` + N × `.woff2`（ASCII 场景 ≤ 8 块 / ≤ 300 KB）；`--atlas-mono` 实际生效（canvas 测宽 ≠ `monospace`） |
| 断开网络后启动 | 不卡、不报错、UI 用回退字体；`link.onerror` 或 3s 超时各记一条 ui-log |
| 直接在地址栏打开 `http://localhost:PORT` 与 `http://127.0.0.1:PORT` | 两种情况都要能加载（no-referrer 同时覆盖两者） |
| `make cbm-with-ui` | 构建通过，`embedded_assets` 正常 |
| `tests/test_httpd.c` | CSP 用例更新后通过；`ASSERT_TRUE(strstr(csp, "*") == NULL)` 仍成立 |
| 刷新两次 | 第二次只剩 `/result.css`（分块命中 immutable 缓存） |

---

## 7. 更稳的替代方案（建议先和项目 owner 讨论再做）

这个仓库的 UI 是**嵌进二进制、只服务 127.0.0.1** 的，引入第三方 CDN 与这个设计取向有摩擦（离线、可复现、CSP 收紧、无外部依赖都是现有契约）。两条替代路线，成本都很低：

**A. 自托管 Latin 子集（推荐）**
Maple Mono 的 ASCII/拉丁子集 woff2 大约 **50–80 KB**，直接放进 `graph-ui/public/fonts/`，由 `embed-frontend.sh` 打进二进制，`@font-face` 用 `url('/fonts/…woff2')`。CSP **不用改**（`font-src 'self'` 已经够），完全离线，没有防盗链、没有 204、没有第三方可用性问题。GUI 主要显示 ASCII 代码，Latin 子集就够 95% 的场景。

**B. A + 只在需要 CJK 时用 CDN**
默认走自托管 Latin 子集；用户真的要看中文标识符时再按 §5 加载 CDN 的 CJK 分块（此时 CJK 分块约 0.3–1.3 MB）。CSP 仍需放行一个 host，但常态零外部请求。

---

## 8. 参考实现与工具（已跑通，可直接抄）

- **同逻辑参考实现**：`/home/n/document/code/fontTest`（Svelte 版）
  - `src/lib/fonts.js` → `detectFamily()` / `detectAll()`（canvas 3 基线 × 2 样本 × 5 度量，含消融实验结论：少一项就会漏检 Arial/Helvetica 或 CJK 全宽字形）
  - `src/App.svelte` → `loadNetworkFont()`（注入 link → `await document.fonts.load()` → 才加进候选列表）
  - `README.md` → 「网络字体」一节，含完整实测表格与防盗链说明
- **测量脚本**：`/tmp/z7test/measure.js`（裸 Chrome + CDP，按 `Network.loadingFinished.encodedDataLength` 统计真实传输字节；支持「加载后执行一段 JS」+「再 reload」两步，用来验证缓存命中与刷新后行为）
  ```bash
  export PATH="$HOME/.bun/bin:$PATH"
  bun /tmp/z7test/measure.js 'http://127.0.0.1:PORT/' 6000
  ```
- **复现防盗链**（一条命令）：
  ```bash
  UA='Mozilla/5.0 (X11; Linux x86_64) Chrome/157'
  curl -s -o /dev/null -w '%{http_code}\n' -A "$UA" -e 'http://127.0.0.1:5180/' \
       'https://fontsapi.zeoseven.com/442/main/result.css'   # → 204
  curl -s -o /dev/null -w '%{http_code}\n' -A "$UA" \
       'https://fontsapi.zeoseven.com/442/main/result.css'   # → 200
  ```

---

## 9. 落地顺序建议

1. `tokens.css` 加 `"Maple Mono NF CN"`（纯收益，无风险，可先合）
2. `installFontFallback()` + `main.tsx` 接线（先不碰 CSP，验证「装了字体的机器零请求」）
3. CSP + `tests/test_httpd.c` 同步改（这一步才真正让 CDN 生效）
4. 按 §6 验收，把实测数字填回本文档
