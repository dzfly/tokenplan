# codexU 风格仪表盘设计

日期：2026-08-27
状态：已确认（用户批准）

## 背景

参照 codexU（/Users/tal/Desktop/work/other/codexU，SwiftUI 深色玻璃卡片风仪表盘）的样式与功能，重做 TalTokenPlan 的展示层。功能集合以 TAL 接口实际支持的字段为准，不支持的功能去掉。

## 接口能力盘点（apx-console-api.tal.com）

| 数据 | 字段 | 支撑的功能 |
|---|---|---|
| `codingPlan/billing` costSummary | used / reserved / limit / remaining / usageRatio | 账单额度环、羊毛进度条 |
| 同上 maxModel* | maxModelUsed / Limit / Remaining / UsageRatio / Percentage | 单模型（Max）额度标注 |
| 同上 tokenUsage | 累计 input/output/cacheRead/cacheWrite | 累计统计卡 |
| `codingPlan/usage` | 逐请求：model / costs(¥) / channelName / tokenUsage / requestTime，支持 startTime/endTime 分页 | 今日/近7天卡、趋势图、模型排行 |
| `codingPlan/channelList` | channel / channelName | （暂不使用） |

## 非目标（接口无数据源，砍掉）

5h/7d 滚动时间窗额度、重置时间/重置次数、任务看板、AI 领导力、Skill/工具 TOP、项目排行、配色系统（多 palette）、中英切换、羊毛进度的 OpenAI 美元分段刻度（TAL 是 ¥ 计费，用线性 ¥used/¥limit）。

## UI 设计

### 主窗口（新增，SwiftUI，固定深色玻璃风）

窗口约 820×560，可调宽高，深蓝底 + 半透明圆角卡片 + 系统红黄绿窗控。布局自上而下：

1. **顶部行**：额度环（剩余% 大字 + 环形进度，数据 costSummary.used/limit/remaining；环下方小字标注 Max 单模型额度，字段缺失时隐藏）+ 右侧三张统计卡（今日 / 近7天 / 累计 token，每卡下方细分条：未缓存输入 / 命中缓存 / 输出，cacheWrite 与 cacheRead 合并为缓存段）
2. **羊毛进度条**：¥used / ¥limit 线性进度条，标注剩余金额
3. **近7日趋势**：每日 token 柱状图（横轴日期，柱顶数值，悬停 .help 显示当日 ¥ 费用与 token）
4. **模型排行**：近7天按 model 聚合的 Top 8 + 「其他」，列：模型名 / token / ¥ / 调用次数 / 占比条

状态：加载中（进度提示）、未登录/登录引导（复用现有 browserLoginPrompt 文案与流程）、网络错误（错误信息 + 重试按钮）。

### 菜单简化（改 MenuBuilder）

参照 codexU popover：标题行（图标 + 刷新按钮）→ 账单概览卡（¥剩余/已用/上限 + 进度条，Max 行可选）→ 今日 token 行 → 按钮行（打开主界面 / 设置 / 退出）→ 上次更新时间。现有「最近用量列表」从菜单移除（明细价值被主窗口趋势/排行覆盖）；登录引导与刷新逻辑保持现状；「打开详情页」槽位改为「打开主界面」。

### 状态栏

StatusBarProgressView 保持现状不动。

## 数据流

- AppDelegate 现有定时刷新管线不动（billing + fetchRecentUsage 喂菜单和状态栏），仅扩展 BillingSnapshot 增加 limit / maxModel 字段供菜单卡使用
- 主窗口独立的 DashboardViewModel（@MainActor ObservableObject）：窗口打开时及手动刷新时拉取 billing + 近7天逐日 usage，派生 今日/近7天统计、趋势、排行。窗口关闭即停止，不参与定时轮询
- APIClient 新增一个公开方法：按天拉取最近 N 天 usage（每天复用现有 fetchDayAllPages 分页，DispatchGroup 并发），返回逐日聚合结果。现有 fetchRecentUsage 语义不动

## 文件改动

新增（平铺跟随现有目录）：

- `MainWindowController.swift` — NSWindow + NSHostingView，固定深色外观，关闭仅隐藏
- `DashboardView.swift` — SwiftUI 根视图（额度环、统计卡、羊毛进度、趋势、排行、状态视图）
- `DashboardViewModel.swift` — 拉取与纯函数派生（逐日聚合 / 模型聚合）
- `DashboardTheme.swift` — 深色玻璃色板、卡片样式、渐变

修改：

- `MenuBuilder.swift` — 按上述简化重写 build/rebuild，删除不再使用的列表渲染；DisplayData 精简为菜单实际所需字段
- `AppDelegate.swift` — 增加 mainWindowController 与 openMainWindow()；updateDisplay 填充扩展后的快照字段
- `APIClient.swift` — 新增近 N 天逐日拉取方法

不动：SettingsWindowController、StatusBarProgressView、TokenStore/TokenParser、CookieReader*、Package.swift、build.sh。

## 错误与边界

- usage 单日失败：该日记 0，整体不失败；billing 失败但 usage 成功 → 额度环/羊毛进度显示 "--"，统计卡正常
- 全部失败 → 错误视图 + 重试
- 401 → 走现有 handleUnauthorized 自动重登流程，主窗口显示登录引导态
- tokenUsage 缺 cache 字段 → 细分条自动隐藏缓存段（复用 hasCacheData 语义）
- 模型名缺失 → 归入「未知」

## 验证

`swift build` 通过；`swift run TalTokenPlan` 手动验证：菜单简化形态、主窗口各板块真实数据渲染、刷新按钮、未登录/错误态（改坏 token 模拟）、窗口关闭后菜单栏应用存活。
