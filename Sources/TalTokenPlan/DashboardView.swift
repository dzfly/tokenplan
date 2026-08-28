import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var themeToken = "\(AppSettings.appearanceMode.rawValue)|\(AppSettings.paletteID)"

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
        .id(themeToken)
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsDidChange)) { _ in
            DashboardTheme.apply()
            themeToken = "\(AppSettings.appearanceMode.rawValue)|\(AppSettings.paletteID)"
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
        ScrollView {
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
                        .frame(width: 240)
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            StatCardView(title: "今日", segment: content.today)
                            StatCardView(title: "近 7 天", segment: content.week)
                            StatCardView(title: "累计", segment: nil, fallbackText: content.cumulativeTokensText)
                        }
                        WoolBarView(content: content)
                    }
                }

                TodayUsageSectionView(entries: content.todayUsage)
            TrendChartView(points: content.trend)
                RankingListView(entries: content.ranking)
            }
            .padding(16)
        }
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
                if let maxFraction {
                    Circle()
                        .stroke(DashboardTheme.trackBackground, lineWidth: 7)
                        .frame(width: 104, height: 104)
                    Circle()
                        .trim(from: 0, to: maxFraction)
                        .stroke(
                            DashboardTheme.purple,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: maxFraction)
                }
                VStack(spacing: 2) {
                    Text(percentText)
                        .font(.system(size: maxFraction == nil ? 30 : 26, weight: .semibold, design: .rounded))
                        .foregroundColor(DashboardTheme.textPrimary)
                    if let maxPercentText {
                        Text("MAX \(maxPercentText)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(DashboardTheme.textSecondary)
                    }
                }
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 4) {
                Text("已用 \(content.usedText) / \(content.limitText)（\(usedPercentDetail)）")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundColor(DashboardTheme.textPrimary)
                if let maxText = content.maxModelText {
                    Text(maxText)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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

    /// Max 内环：已用进度，接口未返回 Max 数据时不显示
    private var maxFraction: Double? {
        guard let maxRatioPct = content.maxRatioPct else { return nil }
        return min(max(maxRatioPct / 100, 0), 1)
    }

    private var maxPercentText: String? {
        guard let maxRatioPct = content.maxRatioPct else { return nil }
        return String(format: "%.0f%%", maxRatioPct)
    }

    private var usedPercentDetail: String {
        guard let ratioPct = content.ratioPct else { return "--" }
        return String(format: "%.1f%%", ratioPct)
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
                Text("使用进度")
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

// MARK: - 今日用量（逐请求明细 + 左右翻页）

private struct TodayUsageSectionView: View {
    let entries: [TodayUsageEntry]
    @State private var page = 0
    private let pageSize = 10

    private var pageCount: Int { max(1, (entries.count + pageSize - 1) / pageSize) }

    var body: some View {
        let safePage = min(page, pageCount - 1)
        let pageEntries = entries.indices.contains(safePage * pageSize)
            ? entries[safePage * pageSize..<min(safePage * pageSize + pageSize, entries.count)]
            : []

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日用量")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DashboardTheme.textPrimary)
                Spacer()
                if pageCount > 1 {
                    HStack(spacing: 10) {
                        Button {
                            if safePage > 0 { page = safePage - 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(DashboardTheme.textSecondary)
                        .disabled(safePage == 0)

                        Text("\(safePage + 1) / \(pageCount)")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.textSecondary)

                        Button {
                            if safePage < pageCount - 1 { page = safePage + 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(DashboardTheme.textSecondary)
                        .disabled(safePage == pageCount - 1)
                    }
                }
            }

            if entries.isEmpty {
                Text("今日暂无用量")
                    .font(.system(size: 11))
                    .foregroundColor(DashboardTheme.textSecondary)
            } else {
                HStack {
                    Text("时间").frame(width: 56, alignment: .leading)
                    Text("模型").frame(maxWidth: .infinity, alignment: .leading)
                    Text("渠道").frame(width: 84, alignment: .leading)
                    Text("输入").frame(width: 56, alignment: .trailing)
                    Text("输出").frame(width: 56, alignment: .trailing)
                    Text("缓存").frame(width: 56, alignment: .trailing)
                    Text("Token").frame(width: 56, alignment: .trailing)
                    Text("金额").frame(width: 68, alignment: .trailing)
                }
                .font(.system(size: 9))
                .foregroundColor(DashboardTheme.textSecondary)

                ForEach(Array(pageEntries.enumerated()), id: \.offset) { _, entry in
                    HStack {
                        Text(entry.timeText)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.textSecondary)
                            .frame(width: 56, alignment: .leading)
                        Text(entry.model)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DashboardTheme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.channel)
                            .font(.system(size: 10))
                            .foregroundColor(DashboardTheme.textSecondary)
                            .lineLimit(1)
                            .frame(width: 84, alignment: .leading)
                        Text(entry.inputText)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.textSecondary)
                            .frame(width: 56, alignment: .trailing)
                        Text(entry.outputText)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.textPrimary)
                            .frame(width: 56, alignment: .trailing)
                        Text(entry.cacheText)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.textSecondary)
                            .frame(width: 56, alignment: .trailing)
                        Text(entry.tokensText)
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.textPrimary)
                            .frame(width: 56, alignment: .trailing)
                        Text(entry.costText)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.textSecondary)
                            .frame(width: 68, alignment: .trailing)
                    }
                }
            }
        }
        .dashboardCard()
        .onChange(of: entries.count) { _ in
            page = min(page, pageCount - 1)
        }
    }
}

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
