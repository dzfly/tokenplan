# codexU 风格仪表盘实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 SwiftUI 新增 codexU 深色玻璃风主窗口（账单额度环 + 今日/近7天/累计 token 统计卡 + 羊毛进度条 + 近7日趋势 + 模型排行），并把菜单简化为 codexU popover 式概览。

**Architecture:** 数据层最小扩展（APIClient 新增按天拉取 7 天 usage 的公开方法）；新增 DashboardViewModel（@MainActor ObservableObject，自带拉取与纯函数派生，窗口打开时刷新）；SwiftUI 视图经 NSHostingController 承载在 NSWindow 中；AppDelegate 现有定时刷新管线只做字段扩展，菜单走 MenuBuilder 重写。

**Tech Stack:** Swift 5.9 / AppKit + SwiftUI（系统框架，无新依赖）/ SPM，macOS 12+

**Spec:** `docs/superpowers/specs/2026-08-27-codexu-style-dashboard-design.md`

## Global Constraints

- 平台 macOS 12（`Package.swift` platforms 不动）：禁用 Charts 框架（macOS 13+）、NavigationStack；图表用 Capsule/手绘
- 不改动：Package.swift、build.sh、SettingsWindowController、StatusBarProgressView、TokenStore/TokenParser、CookieReader*、Helper target
- UI 文案全部简体中文；深色玻璃配色固定，不跟随系统明暗
- 本项目**没有测试 target**（spec 约定不动 Package.swift，故不加）：每个任务的验证 = `swift build` 零错误 + 最终 `swift run TalTokenPlan` 人工验证
- **不做 git commit**（用户规则：仅在明确要求时提交）；全部任务完成后统一询问用户是否提交
- 复用现有格式化函数：`MenuBuilder.formatTokens` / `formatBillingCost` / `formatUsageCost`（勿重复实现）

---

### Task 1: APIClient 新增近 N 天逐日拉取

**Files:**
- Modify: `Sources/TalTokenPlan/APIClient.swift`（在 `fetchRecentUsage` 之后、`private func fetchUsage` 之前插入新代码）

**Interfaces:**
- Consumes: 现有 `private func fetchDayAllPages(startMs:endMs:pageSize:completion:)`（APIClient.swift:180）
- Produces: `struct DailyUsage { let dayStart: Date; let items: [UsageResponse.UsageItem] }`；`APIClient.fetchRecentDailyUsage(days: Int = 7, completion: (Result<[DailyUsage], APIError>) -> Void)`，返回数组按 今天→N天前 排序；单日请求失败按空列表处理，401/403 时整体 `.failure(.unauthorized)`

- [ ] **Step 1: 在 APIClient.swift 的 `fetchRecentUsage` 方法（约 133 行 `}` 之后）插入以下代码**

```swift
    struct DailyUsage {
        let dayStart: Date
        let items: [UsageResponse.UsageItem]
    }

    /// 并发拉取最近 days 天（含今天）的逐日用量，返回按 今天→N天前 排序。
    /// 单日失败（网络/解码）按空数据处理，不导致整体失败；401/403 时整体返回 unauthorized。
    func fetchRecentDailyUsage(
        days: Int = 7,
        completion: @escaping (Result<[DailyUsage], APIError>) -> Void
    ) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var results = [DailyUsage?](repeating: nil, count: days)
        let group = DispatchGroup()
        let lock = NSLock()
        var unauthorized = false

        for offset in 0..<days {
            let dayStart = cal.date(byAdding: .day, value: -offset, to: todayStart)!
            let end: Date = offset == 0
                ? Date()
                : dayStart.addingTimeInterval(24 * 60 * 60 - 1)
            let startMs = String(Int64(dayStart.timeIntervalSince1970 * 1000))
            let endMs = String(Int64(end.timeIntervalSince1970 * 1000))

            group.enter()
            fetchDayAllPages(startMs: startMs, endMs: endMs, pageSize: 500) { result in
                defer { group.leave() }
                switch result {
                case .success(let response):
                    lock.lock()
                    results[offset] = DailyUsage(dayStart: dayStart, items: response.list ?? [])
                    lock.unlock()
                case .failure(.unauthorized):
                    lock.lock()
                    unauthorized = true
                    lock.unlock()
                case .failure:
                    break // 单日失败按空处理（spec：单日失败记 0，整体不失败）
                }
            }
        }

        group.notify(queue: .main) {
            if unauthorized {
                completion(.failure(.unauthorized))
                return
            }
            let assembled = (0..<days).map { offset -> DailyUsage in
                if let r = results[offset] { return r }
                let day = cal.date(byAdding: .day, value: -offset, to: todayStart)!
                return DailyUsage(dayStart: day, items: [])
            }
            completion(.success(assembled))
        }
    }
```

- [ ] **Step 2: 编译验证**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`，无 warning 新增

---

### Task 2: DashboardViewModel（数据模型 + 派生 + 拉取）

**Files:**
- Create: `Sources/TalTokenPlan/DashboardViewModel.swift`

**Interfaces:**
- Consumes: Task 1 的 `APIClient.fetchRecentDailyUsage`；现有 `APIClient.fetchBilling`、`BillingData`、`TokenUsageDetail`、`MenuBuilder.formatTokens/formatBillingCost`
- Produces（Task 3/4/5 依赖，签名精确如下）:

```swift
struct UsageSegmentSet { var plainInput: Int64; var cacheRead: Int64; var cacheWrite: Int64; var output: Int64; var total: Int64; var cost: Double; var requests: Int }
struct DayPoint { let day: Date; let tokens: Int64; let cost: Double }
struct ModelRankEntry { let model: String; let tokens: Int64; let cost: Double; let requests: Int; let share: Double }
struct DashboardContent {
    let ratioPct: Double?          // 账单已用百分比，billing 缺失时 nil
    let usedText: String           // "¥123.4"，billing 缺失时 "-"
    let remainingText: String
    let limitText: String
    let maxModelText: String?      // "Max ¥12.3 / ¥100.0 (12.3%)"，字段缺失时 nil
    let cumulativeTokensText: String
    let today: UsageSegmentSet
    let week: UsageSegmentSet
    let trend: [DayPoint]          // 最旧在左
    let ranking: [ModelRankEntry]
    let lastUpdatedText: String
}
@MainActor final class DashboardViewModel: ObservableObject {
    enum State { case idle, loading, loaded(DashboardContent), failed(String), needsLogin }
    @Published private(set) var state: State
    @Published private(set) var isRefreshing: Bool
    var onUnauthorized: (() -> Void)?
    var onBrowserLogin: (() -> Void)?
    func refresh()
    // 纯函数（static，便于人工验证）：
    static func aggregateSegments(from items: [UsageResponse.UsageItem]) -> UsageSegmentSet
    static func dayPoints(from daily: [DailyUsage]) -> [DayPoint]
    static func ranking(from items: [UsageResponse.UsageItem], topN: Int = 8) -> [ModelRankEntry]
}
```

- [ ] **Step 1: 创建 `Sources/TalTokenPlan/DashboardViewModel.swift`，写入以下完整内容**

```swift
import Foundation
import Combine

struct UsageSegmentSet {
    var plainInput: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheWrite: Int64 = 0
    var output: Int64 = 0
    var total: Int64 = 0
    var cost: Double = 0
    var requests: Int = 0

    var cacheAll: Int64 { cacheRead + cacheWrite }
}

struct DayPoint {
    let day: Date
    let tokens: Int64
    let cost: Double
}

struct ModelRankEntry {
    let model: String
    let tokens: Int64
    let cost: Double
    let requests: Int
    let share: Double
}

struct DashboardContent {
    let ratioPct: Double?
    let usedText: String
    let remainingText: String
    let limitText: String
    let maxModelText: String?
    let cumulativeTokensText: String
    let today: UsageSegmentSet
    let week: UsageSegmentSet
    let trend: [DayPoint]
    let ranking: [ModelRankEntry]
    let lastUpdatedText: String
}

@MainActor
final class DashboardViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded(DashboardContent)
        case failed(String)
        case needsLogin
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isRefreshing = false

    var onUnauthorized: (() -> Void)?
    var onBrowserLogin: (() -> Void)?

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        if case .loaded = state {} else { state = .loading }

        var billing: BillingData?
        var daily: [APIClient.DailyUsage]?
        var sawUnauthorized = false
        var billingFailed = false

        let group = DispatchGroup()
        group.enter()
        APIClient.shared.fetchBilling { result in
            switch result {
            case .success(let d): billing = d
            case .failure(.unauthorized): sawUnauthorized = true
            case .failure: billingFailed = true
            }
            group.leave()
        }
        group.enter()
        APIClient.shared.fetchRecentDailyUsage(days: 7) { result in
            switch result {
            case .success(let d): daily = d
            case .failure(.unauthorized): sawUnauthorized = true
            case .failure: break // usage 整批失败按空数据处理
            }
            group.leave()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isRefreshing = false
            if sawUnauthorized {
                self.state = .needsLogin
                self.onUnauthorized?()
                return
            }
            if billing == nil && daily == nil {
                if case .loaded = self.state {} else {
                    self.state = .failed("网络请求失败，请检查网络后重试")
                }
                return
            }
            self.state = .loaded(Self.makeContent(billing: billing, daily: daily ?? []))
        }
    }

    // MARK: - 派生（纯函数）

    static func makeContent(billing: BillingData?, daily: [APIClient.DailyUsage]) -> DashboardContent {
        let allItems = daily.flatMap(\.items)
        let todayItems = daily.first?.items ?? []

        var ratioPct: Double?
        var usedText = "-"
        var remainingText = "-"
        var limitText = "-"
        var maxModelText: String?
        if let cs = billing?.costSummary {
            let ratio = cs.usageRatio ?? (cs.limit > 0 ? cs.used / cs.limit : 0)
            ratioPct = ratio * 100
            usedText = MenuBuilder.formatBillingCost(cs.used)
            remainingText = MenuBuilder.formatBillingCost(cs.remaining)
            limitText = MenuBuilder.formatBillingCost(cs.limit)
            if let maxUsed = cs.maxModelUsed, let maxLimit = cs.maxModelLimit, maxLimit > 0 {
                let r = cs.maxModelUsageRatio ?? (maxUsed / maxLimit)
                maxModelText = "Max \(MenuBuilder.formatBillingCost(maxUsed)) / \(MenuBuilder.formatBillingCost(maxLimit))（\(String(format: "%.1f", r * 100))%）"
            }
        }

        let cumulativeText = billing?.tokenUsage.flatMap { $0.totalTokens }
            .map(MenuBuilder.formatTokens) ?? "-"

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"

        return DashboardContent(
            ratioPct: ratioPct,
            usedText: usedText,
            remainingText: remainingText,
            limitText: limitText,
            maxModelText: maxModelText,
            cumulativeTokensText: cumulativeText,
            today: aggregateSegments(from: todayItems),
            week: aggregateSegments(from: allItems),
            trend: dayPoints(from: daily),
            ranking: ranking(from: allItems),
            lastUpdatedText: fmt.string(from: Date())
        )
    }

    /// Anthropic 计费语义：inputTokens 已含 cache_read/cache_write，未缓存输入 = input - cache
    static func aggregateSegments(from items: [UsageResponse.UsageItem]) -> UsageSegmentSet {
        var s = UsageSegmentSet()
        for item in items {
            guard let u = item.tokenUsage else { continue }
            let input = u.inputTokens ?? 0
            s.cacheRead += u.cacheRead
            s.cacheWrite += u.cacheWrite
            s.output += u.outputTokens ?? 0
            s.total += u.totalTokens ?? 0
            s.cost += item.costs ?? 0
            s.requests += 1
            s.plainInput += max(0, input - u.cacheRead - u.cacheWrite)
        }
        return s
    }

    static func dayPoints(from daily: [APIClient.DailyUsage]) -> [DayPoint] {
        daily.map { d in
            DayPoint(
                day: d.dayStart,
                tokens: d.items.compactMap { $0.tokenUsage?.totalTokens }.reduce(0, +),
                cost: d.items.compactMap { $0.costs }.reduce(0, +)
            )
        }
        .reversed() // 最旧在左
    }

    static func ranking(from items: [UsageResponse.UsageItem], topN: Int = 8) -> [ModelRankEntry] {
        var tokens: [String: Int64] = [:]
        var costs: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for item in items {
            let name = item.model ?? "未知"
            tokens[name, default: 0] += item.tokenUsage?.totalTokens ?? 0
            costs[name, default: 0] += item.costs ?? 0
            counts[name, default: 0] += 1
        }
        let total = tokens.values.reduce(Int64(0), +)
        let sorted = tokens.sorted { $0.value > $1.value }
        guard !sorted.isEmpty else { return [] }

        var entries: [ModelRankEntry] = []
        for (idx, kv) in sorted.enumerated() where idx < topN {
            entries.append(ModelRankEntry(
                model: kv.key,
                tokens: kv.value,
                cost: costs[kv.key] ?? 0,
                requests: counts[kv.key] ?? 0,
                share: total > 0 ? Double(kv.value) / Double(total) : 0
            ))
        }
        if sorted.count > topN {
            let rest = sorted.dropFirst(topN)
            let t = rest.reduce(Int64(0)) { $0 + $1.value }
            let c = rest.reduce(0.0) { $0 + (costs[$1.key] ?? 0) }
            let n = rest.reduce(0) { $0 + (counts[$1.key] ?? 0) }
            entries.append(ModelRankEntry(
                model: "其他",
                tokens: t,
                cost: c,
                requests: n,
                share: total > 0 ? Double(t) / Double(total) : 0
            ))
        }
        return entries
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

---

### Task 3: DashboardTheme + DashboardView（SwiftUI 主界面）

**Files:**
- Create: `Sources/TalTokenPlan/DashboardTheme.swift`
- Create: `Sources/TalTokenPlan/DashboardView.swift`

**Interfaces:**
- Consumes: Task 2 全部类型；`MenuBuilder.formatTokens/formatBillingCost`
- Produces: `struct DashboardView: View { @ObservedObject var viewModel: DashboardViewModel }`（Task 4 使用）

- [ ] **Step 1: 创建 `Sources/TalTokenPlan/DashboardTheme.swift`**

```swift
import SwiftUI

enum DashboardTheme {
    static let windowBackground = Color(red: 0.043, green: 0.067, blue: 0.118)
    static let cardBackground = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let trackBackground = Color.white.opacity(0.10)

    static let blue = Color(red: 0.31, green: 0.56, blue: 0.97)
    static let purple = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)

    static let ringGradient = LinearGradient(
        colors: [blue, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct DashboardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DashboardTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DashboardTheme.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    func dashboardCard() -> some View {
        modifier(DashboardCardModifier())
    }
}
```

- [ ] **Step 2: 创建 `Sources/TalTokenPlan/DashboardView.swift`**

```swift
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ZStack {
            DashboardTheme.windowBackground.ignoresSafeArea()
            switch viewModel.state {
            case .idle, .loading:
                LoadingView()
            case .loaded(let content):
                LoadedDashboardView(
                    content: content,
                    isRefreshing: viewModel.isRefreshing,
                    onRefresh: { viewModel.refresh() }
                )
            case .failed(let message):
                ErrorView(message: message) { viewModel.refresh() }
            case .needsLogin:
                NeedsLoginView { viewModel.onBrowserLogin?() }
            }
        }
    }
}

// MARK: - 加载 / 错误 / 登录态

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("加载中…")
                .font(.system(size: 13))
                .foregroundColor(DashboardTheme.textSecondary)
        }
    }
}

private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundColor(DashboardTheme.textSecondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(DashboardTheme.textSecondary)
            Button("重试") { onRetry() }
                .controlSize(.regular)
        }
    }
}

private struct NeedsLoginView: View {
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 30))
                .foregroundColor(DashboardTheme.textSecondary)
            Text("未检测到登录凭证")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DashboardTheme.textPrimary)
            Text("请在浏览器登录 cloud.tal.com 后获取凭证")
                .font(.system(size: 12))
                .foregroundColor(DashboardTheme.textSecondary)
            Button("在浏览器中登录") { onLogin() }
                .controlSize(.large)
        }
    }
}

// MARK: - 主内容

private struct LoadedDashboardView: View {
    let content: DashboardContent
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Tal Token Plan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DashboardTheme.textPrimary)
                Spacer()
                Text("更新于 \(content.lastUpdatedText)")
                    .font(.system(size: 11))
                    .foregroundColor(DashboardTheme.textSecondary)
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(DashboardTheme.textSecondary)
                .disabled(isRefreshing)
            }

            HStack(alignment: .top, spacing: 12) {
                QuotaRingCard(content: content)
                    .frame(width: 210)
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        StatCardView(title: "今日", segment: content.today)
                        StatCardView(title: "近 7 天", segment: content.week)
                        StatCardView(title: "累计", segment: nil, fallbackText: content.cumulativeTokensText)
                    }
                    WoolBarView(content: content)
                }
            }

            TrendChartView(points: content.trend)
            RankingListView(entries: content.ranking)
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

// MARK: - 额度环卡片

private struct QuotaRingCard: View {
    let content: DashboardContent

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(DashboardTheme.trackBackground, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        DashboardTheme.ringGradient,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: fraction)
                VStack(spacing: 2) {
                    Text(percentText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundColor(DashboardTheme.textPrimary)
                    Text("已用")
                        .font(.system(size: 11))
                        .foregroundColor(DashboardTheme.textSecondary)
                }
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 4) {
                Text("剩余 \(content.remainingText) / \(content.limitText)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DashboardTheme.textPrimary)
                if let maxText = content.maxModelText {
                    Text(maxText)
                        .font(.system(size: 10))
                        .foregroundColor(DashboardTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .dashboardCard()
    }

    private var fraction: Double {
        guard let ratioPct = content.ratioPct else { return 0 }
        return min(max(ratioPct / 100, 0), 1)
    }

    private var percentText: String {
        guard let ratioPct = content.ratioPct else { return "--" }
        return String(format: "%.0f%%", ratioPct)
    }
}

// MARK: - token 统计卡

private struct StatCardView: View {
    let title: String
    let segment: UsageSegmentSet?
    var fallbackText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(DashboardTheme.textSecondary)
            Text(tokensText)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(DashboardTheme.textPrimary)
            if let s = segment {
                SegmentBarRow(label: "未缓存", value: s.plainInput, total: s.total, color: DashboardTheme.blue)
                SegmentBarRow(label: "缓存", value: s.cacheAll, total: s.total, color: DashboardTheme.purple)
                SegmentBarRow(label: "输出", value: s.output, total: s.total, color: DashboardTheme.green)
            } else {
                Text("含输入 / 缓存 / 输出")
                    .font(.system(size: 10))
                    .foregroundColor(DashboardTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }

    private var tokensText: String {
        if let s = segment { return MenuBuilder.formatTokens(s.total) }
        return fallbackText.isEmpty ? "-" : fallbackText
    }
}

private struct SegmentBarRow: View {
    let label: String
    let value: Int64
    let total: Int64
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(DashboardTheme.textSecondary)
                Spacer()
                Text(MenuBuilder.formatTokens(value))
                    .font(.system(size: 9))
                    .foregroundColor(DashboardTheme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DashboardTheme.trackBackground)
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 4)
        }
    }

    private var ratio: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(value) / Double(total), 0), 1)
    }
}

// MARK: - 羊毛进度条

private struct WoolBarView: View {
    let content: DashboardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("羊毛进度")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DashboardTheme.textPrimary)
                Spacer()
                Text("已用 \(content.usedText) / 上限 \(content.limitText)")
                    .font(.system(size: 11))
                    .foregroundColor(DashboardTheme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DashboardTheme.trackBackground)
                    Capsule()
                        .fill(DashboardTheme.green)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
        .dashboardCard()
    }

    private var fraction: Double {
        guard let ratioPct = content.ratioPct else { return 0 }
        return min(max(ratioPct / 100, 0), 1)
    }
}
```

- [ ] **Step 3: 续写 `DashboardView.swift`（趋势图 + 模型排行）**

```swift
// MARK: - 近 7 日趋势

private struct TrendChartView: View {
    let points: [DayPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("近 7 日趋势")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DashboardTheme.textPrimary)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    VStack(spacing: 4) {
                        Text(MenuBuilder.formatTokens(point.tokens))
                            .font(.system(size: 9))
                            .foregroundColor(DashboardTheme.textSecondary)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(DashboardTheme.ringGradient)
                            .frame(height: barHeight(tokens: point.tokens))
                            .frame(maxWidth: 34)
                        Text(dayLabel(point.day))
                            .font(.system(size: 9))
                            .foregroundColor(DashboardTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help(tip(point))
                }
            }
            .frame(height: 120)
        }
        .dashboardCard()
    }

    private func barHeight(tokens: Int64) -> CGFloat {
        let maxTokens = points.map(\.tokens).max() ?? 0
        guard maxTokens > 0 else { return 2 }
        return max(2, CGFloat(Double(tokens) / Double(maxTokens)) * 88)
    }

    private func dayLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return fmt.string(from: date)
    }

    private func tip(_ point: DayPoint) -> String {
        "\(dayLabel(point.day)) · \(MenuBuilder.formatTokens(point.tokens)) · \(MenuBuilder.formatBillingCost(point.cost))"
    }
}

// MARK: - 模型排行

private struct RankingListView: View {
    let entries: [ModelRankEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模型排行（近 7 天）")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DashboardTheme.textPrimary)
            if entries.isEmpty {
                Text("暂无用量数据")
                    .font(.system(size: 11))
                    .foregroundColor(DashboardTheme.textSecondary)
            } else {
                HStack {
                    Text("模型").frame(width: 150, alignment: .leading)
                    Spacer()
                    Text("Token").frame(width: 70, alignment: .trailing)
                    Text("金额").frame(width: 80, alignment: .trailing)
                    Text("次数").frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 9))
                .foregroundColor(DashboardTheme.textSecondary)

                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(spacing: 3) {
                        HStack {
                            Text(entry.model)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DashboardTheme.textPrimary)
                                .lineLimit(1)
                                .frame(width: 150, alignment: .leading)
                            Spacer()
                            Text(MenuBuilder.formatTokens(entry.tokens))
                                .font(.system(size: 11))
                                .foregroundColor(DashboardTheme.textPrimary)
                                .frame(width: 70, alignment: .trailing)
                            Text(MenuBuilder.formatBillingCost(entry.cost))
                                .font(.system(size: 11))
                                .foregroundColor(DashboardTheme.textSecondary)
                                .frame(width: 80, alignment: .trailing)
                            Text("\(entry.requests)")
                                .font(.system(size: 11))
                                .foregroundColor(DashboardTheme.textSecondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DashboardTheme.trackBackground)
                                Capsule()
                                    .fill(DashboardTheme.blue)
                                    .frame(width: max(2, geo.size.width * entry.share))
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
        }
        .dashboardCard()
    }
}
```

- [ ] **Step 4: 编译验证**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

---

### Task 4: MainWindowController（窗口承载）

**Files:**
- Create: `Sources/TalTokenPlan/MainWindowController.swift`

**Interfaces:**
- Consumes: Task 3 的 `DashboardView(viewModel:)`
- Produces: `final class MainWindowController: NSWindowController { init(viewModel: DashboardViewModel); func showDashboard() }`（Task 5 使用）

- [ ] **Step 1: 创建 `Sources/TalTokenPlan/MainWindowController.swift`**

```swift
import AppKit
import SwiftUI

final class MainWindowController: NSWindowController {
    init(viewModel: DashboardViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tal Token Plan"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(
            calibratedRed: 0.043, green: 0.067, blue: 0.118, alpha: 1
        )
        // 关闭仅隐藏窗口，菜单栏应用继续运行（codexU 同款行为）
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: DashboardView(viewModel: viewModel)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`（窗口尚未接线，属预期）

---

### Task 5: MenuBuilder 简化 + BillingSnapshot 扩展 + AppDelegate 接线

**Files:**
- Modify: `Sources/TalTokenPlan/StatusBarProgressView.swift:10-14`（BillingSnapshot 加字段）
- Modify: `Sources/TalTokenPlan/MenuBuilder.swift`（大改：DisplayData 精简、Action 改名、populate 重写、删除用量列表）
- Modify: `Sources/TalTokenPlan/AppDelegate.swift`（updateDisplay 重写、openMainWindow、闭包改名）

**Interfaces:**
- Consumes: Task 4 的 `MainWindowController`；现有 StatusBarState/BillingSnapshot
- Produces: 菜单 `MenuActionHost.Action.openMain`；`BillingSnapshot` 新字段 `limit/maxModelUsed/maxModelLimit/maxModelRatioPct`（均有默认值，StatusBarProgressView 只读旧三字段不受影响）

- [ ] **Step 1: 扩展 BillingSnapshot（StatusBarProgressView.swift 顶部）**

将：

```swift
struct BillingSnapshot {
    var ratioPct: Double
    var remaining: Double
    var used: Double
}
```

改为：

```swift
struct BillingSnapshot {
    var ratioPct: Double
    var remaining: Double
    var used: Double
    var limit: Double = 0
    var maxModelUsed: Double? = nil
    var maxModelLimit: Double? = nil
    var maxModelRatioPct: Double? = nil
}
```

（带默认值 → AppDelegate 现有 `BillingSnapshot(ratioPct:remaining:used:)` 调用在 Step 3 改造前也能编译。）

- [ ] **Step 2: 重写 MenuBuilder.swift**

2a. `DisplayData`（第 11-19 行）替换为：

```swift
struct DisplayData {
    var billing: BillingSnapshot?
    var todayTokens: String = ""
    var todayCost: String = ""
    var lastUpdated: String = ""
}
```

删除 `UsageItem` 结构体（第 4-9 行）。

2b. `MenuActionHost.Action`（第 106-114 行）中 `case detail = 2` 改为 `case openMain = 2`（其余 case 不动）。

2c. `Style` 枚举（第 190-219 行）：删除 `usageFontSize / usageColumnGap / usageContentInsetX / usageRowSpacing` 四个常量；其余保留。

2d. 删除以下成员（不再被引用）：`headerItem`（约 300 行）、`usageRow`（约 436-505 行）。

2e. `build` / `rebuild` / `populate` 三个方法签名中 `onOpenDetail: @escaping () -> Void` 参数改名 `onOpenMain: @escaping () -> Void`；`populate` 内 `host.set(.detail, handler: onOpenDetail)` 改为 `host.set(.openMain, handler: onOpenMain)`。

2f. `populate` 登录分支（第 589-643 行）整体替换为：

```swift
        if isLoggedIn {
            menu.addItem(headerWithIconButton("账单概览", host: host, buttons: [
                HeaderIconButton(action: .refresh, symbolName: "arrow.clockwise", accessibilityDesc: "刷新", keepsMenuOpen: true),
            ]))
            var rows: [CardRow] = []
            if let b = data.billing {
                rows.append(dataRow("剩余: \(MenuBuilder.formatBillingCost(b.remaining)) / \(MenuBuilder.formatBillingCost(b.limit))"))
                rows.append(progressRow(ratio: b.ratioPct / 100, color: .controlAccentColor))
                rows.append(dataRow("已用: \(MenuBuilder.formatBillingCost(b.used))（\(String(format: "%.1f", b.ratioPct))%）"))
                if let maxUsed = b.maxModelUsed, let maxLimit = b.maxModelLimit {
                    let pctText = b.maxModelRatioPct.map { String(format: "%.1f", $0) } ?? "-"
                    rows.append(dataRow("Max: \(MenuBuilder.formatBillingCost(maxUsed)) / \(MenuBuilder.formatBillingCost(maxLimit))（\(pctText)%）"))
                }
                rows.append(separatorRow())
                rows.append(dataRow("今日 Token: \(data.todayTokens)   金额: \(data.todayCost)"))
            } else {
                rows.append(buttonRow(title: "暂无数据，点击刷新", symbolName: "arrow.clockwise",
                                      action: .refresh, host: host, hintStyle: true))
            }
            menu.addItem(cardItem(rows: rows))

            menu.addItem(spacerItem(height: 6))
            menu.addItem(cardItem(rows: [
                buttonRow(title: "打开主界面", symbolName: "macwindow", action: .openMain, host: host),
                separatorRow(),
                buttonRow(title: "设置", symbolName: "gearshape", action: .settings, host: host),
                separatorRow(),
                buttonRow(title: "退出", symbolName: "power", action: .quit, host: host),
            ]))

            if !data.lastUpdated.isEmpty {
                let cap = NSMenuItem()
                cap.attributedTitle = Style.hint("上次更新: \(data.lastUpdated)")
                cap.isEnabled = false
                menu.addItem(cap)
            }
        } else {
```

（未登录分支与原文件第 644-659 行保持一致，不动。）

2g. 新增 `progressRow`（放在 `separatorRow()` 之后）：

```swift
    /// 卡片内细进度条行（codexU popover 风格）
    private static func progressRow(ratio: Double, color: NSColor) -> CardRow {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.18).cgColor
        container.layer?.cornerRadius = 3
        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.backgroundColor = color.cgColor
        fill.layer?.cornerRadius = 3
        container.addSubview(fill)
        let clamped = min(max(ratio, 0), 1)
        return CardRow(view: container, height: 6) { frame in
            fill.frame = NSRect(x: 0, y: 0, width: frame.width * CGFloat(clamped), height: frame.height)
        }
    }
```

2h. 删除仅被旧列表使用的格式化函数：`formatCacheHitRate`、`formatRequestTime`（第 688-701 行）。保留 `formatTokens / formatBillingCost / formatUsageCost`（AppDelegate 与 Dashboard 仍在用）。

- [ ] **Step 3: 改造 AppDelegate.swift**

3a. 属性区（第 7 行 `settingsWindow` 旁）新增：

```swift
    private var mainWindowController: MainWindowController?
    private var dashboardViewModel: DashboardViewModel?
```

3b. `makeStatusMenu`（第 137 行）与 `rebuildActiveMenu`（第 182 行）中的 `onOpenDetail: { [weak self] in self?.openDetailPage() },` 改为：

```swift
            onOpenMain: { [weak self] in self?.openMainWindow() },
```

3c. `refresh()` 的 `group.notify` 成功路径（第 255-256 行）在 `self.refreshActiveMenuIfNeeded()` 后新增一行：

```swift
            if let window = self.mainWindowController?.window, window.isVisible {
                self.dashboardViewModel?.refresh()
            }
```

3d. `updateDisplay`（第 282-373 行）整体替换为：

```swift
    private func updateDisplay(billing: BillingData?, usage: UsageResponse?) {
        if billing == nil && usage == nil { return }

        var data = DisplayData()
        data.billing = displayData.billing
        data.todayTokens = displayData.todayTokens
        data.todayCost = displayData.todayCost

        if let b = billing {
            let cs = b.costSummary
            let ratioPct = (cs.usageRatio ?? (cs.limit > 0 ? cs.used / cs.limit : 0)) * 100
            var maxRatioPct: Double?
            if let maxUsed = cs.maxModelUsed, let maxLimit = cs.maxModelLimit, maxLimit > 0 {
                maxRatioPct = (cs.maxModelUsageRatio ?? maxUsed / maxLimit) * 100
            }
            data.billing = BillingSnapshot(
                ratioPct: ratioPct,
                remaining: cs.remaining,
                used: cs.used,
                limit: cs.limit,
                maxModelUsed: cs.maxModelUsed,
                maxModelLimit: cs.maxModelLimit,
                maxModelRatioPct: maxRatioPct
            )
            updateStatusBar(state: .data(data.billing!))
        }

        if let usage {
            let list = usage.list ?? []
            let agg = TokenUsageDetail.aggregate(from: list)
            data.todayTokens = MenuBuilder.formatTokens(agg.totalTokens)
            data.todayCost = MenuBuilder.formatUsageCost(list.compactMap { $0.costs }.reduce(0, +))
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        data.lastUpdated = fmt.string(from: Date())
        displayData = data
    }
```

3e. 在 `showSettings()`（第 656 行）之后新增：

```swift
    private func openMainWindow() {
        if mainWindowController == nil {
            let vm = DashboardViewModel()
            vm.onUnauthorized = { [weak self] in self?.handleUnauthorized() }
            vm.onBrowserLogin = { [weak self] in self?.startBrowserLoginFlow() }
            dashboardViewModel = vm
            mainWindowController = MainWindowController(viewModel: vm)
        }
        mainWindowController?.showDashboard()
        dashboardViewModel?.refresh()
    }
```

- [ ] **Step 4: 全量编译 + 引用检查**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

Run: `grep -rn "usageItems\|usageLines\|billingLines\|formatRequestTime\|formatCacheHitRate\|UsageItem\b" Sources/TalTokenPlan/ | grep -v "UsageResponse.UsageItem"`
Expected: 无输出（旧列表代码已清干净）

---

### Task 6: 人工验证（用户协助）

**Files:** 无代码改动

- [ ] **Step 1: 启动应用**

Run: `swift run TalTokenPlan`（后台运行）

- [ ] **Step 2: 金路径检查（人工）**

- 菜单栏点击图标：新版菜单 = 账单概览卡（剩余/进度条/已用/Max/今日）+ 三按钮 + 上次更新
- 「打开主界面」→ 深色玻璃窗口出现：额度环、今日/近7天/累计三卡（含细分条）、羊毛进度、近7日趋势、模型排行
- 主窗口刷新按钮 → 数据更新、按钮禁用恢复
- 关闭窗口 → 菜单栏图标仍在，可再次打开
- 「设置」→ 原 AppKit 设置窗正常打开
- 状态栏进度环显示不变

- [ ] **Step 3: 边界检查（人工）**

- `TokenStore.delete()` 后（或用无效 token）触发 401：主窗口显示登录引导态；浏览器登录成功后数据恢复
- 断网点刷新：主窗口错误态 + 重试按钮；菜单显示"暂无数据"
- billing 有数据但 usage 空（新账号）：环正常、统计卡为 0、排行"暂无用量数据"

- [ ] **Step 4: 验证通过后询问用户是否 git commit（勿自动提交）**

---

## Self-Review 结论

- **Spec 覆盖**：额度环/Max 标注（Task 3 QuotaRingCard + Task 5 菜单）、三统计卡+细分条（StatCardView）、羊毛进度（WoolBarView）、趋势（TrendChartView）、排行 Top8+其他（RankingListView）、菜单简化（Task 5）、登录/错误/加载态（DashboardView switch）、单日失败容错（Task 1 注释）、累计= billing.tokenUsage（makeContent）、状态栏不动（Global Constraints）✅
- **占位符扫描**：无 TBD/TODO/「类似 Task N」；羊毛进度使用 `DashboardContent.usedText` 直读（Task 2 定义 + makeContent 赋值，Task 3 消费），无文本反解 ✅
- **类型一致性**：`fetchRecentDailyUsage`/`DailyUsage`（Task 1 ↔ Task 2）、`DashboardContent`/`UsageSegmentSet`/`DayPoint`/`ModelRankEntry`（Task 2 ↔ 3）、`DashboardView(viewModel:)`（Task 3 ↔ 4）、`MainWindowController(viewModel:)`/`showDashboard()`（Task 4 ↔ 5）、`Action.openMain`/`onOpenMain`（Task 5 内部）✅
