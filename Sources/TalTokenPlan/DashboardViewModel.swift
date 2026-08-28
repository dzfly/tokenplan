import Foundation
import Combine

struct UsageSegmentSet {
    var plainInput: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheWrite: Int64 = 0
    var output: Int64 = 0
    var total: Int64 = 0

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

struct TodayUsageEntry {
    let timeText: String
    let model: String
    let channel: String
    let inputText: String
    let outputText: String
    let cacheText: String
    let tokensText: String
    let costText: String
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
    let todayUsage: [TodayUsageEntry]
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

        let group = DispatchGroup()
        group.enter()
        APIClient.shared.fetchBilling { result in
            switch result {
            case .success(let d): billing = d
            case .failure(.unauthorized): sawUnauthorized = true
            case .failure: break
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

        // 今日逐请求明细，按时间倒序（最新在前）
        let todayUsage = todayItems
            .sorted { ($0.requestTime ?? 0) > ($1.requestTime ?? 0) }
            .map { item in
                let u = item.tokenUsage
                return TodayUsageEntry(
                    timeText: timeText(item.requestTime),
                    model: item.model ?? "未知",
                    channel: item.channelName ?? "-",
                    inputText: MenuBuilder.formatTokens(u?.inputTokens),
                    outputText: MenuBuilder.formatTokens(u?.outputTokens),
                    cacheText: MenuBuilder.formatTokens(
                        u == nil ? nil : (u!.cacheRead + u!.cacheWrite)
                    ),
                    tokensText: MenuBuilder.formatTokens(u?.totalTokens),
                    costText: item.costs.map { MenuBuilder.formatUsageCost($0) } ?? "-"
                )
            }

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
            todayUsage: todayUsage,
            trend: dayPoints(from: daily),
            ranking: ranking(from: allItems),
            lastUpdatedText: fmt.string(from: Date())
        )
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func timeText(_ ts: Int64?) -> String {
        guard let ts, ts > 0 else { return "--:--:--" }
        let seconds: TimeInterval = ts > 1_000_000_000_000 ? TimeInterval(ts) / 1000 : TimeInterval(ts)
        return timeFormatter.string(from: Date(timeIntervalSince1970: seconds))
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
            s.plainInput += max(0, input - u.cacheRead - u.cacheWrite)
        }
        return s
    }

    static func dayPoints(from daily: [APIClient.DailyUsage]) -> [DayPoint] {        daily.map { d in
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
