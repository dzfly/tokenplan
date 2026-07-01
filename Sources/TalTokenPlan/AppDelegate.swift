import AppKit

@objc final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusBarView: StatusBarProgressView!
    private var refreshTimer: Timer?
    private var settingsWindow: SettingsWindowController?
    private var displayData = DisplayData()
    private var isLoading = false
    private var isLoggedIn = false
    private var isVerifyingLogin = false
    private var isHandlingUnauthorized = false
    private var browserLoginPrompt: BrowserLoginPrompt = .needsLogin
    private var loginPollTimer: Timer?
    private var loginTimeoutTimer: Timer?
    private var isAutoFetchingCookie = false
    /// Cookie 写入有延迟，验证失败时延迟重试的次数与定时器
    private var loginRetryCount = 0
    private static let maxLoginRetry = 3
    private static let loginRetryInterval: TimeInterval = 4
    private var loginRetryTimer: Timer?

    private static let loginPollInterval: TimeInterval = 3
    private static let loginTimeout: TimeInterval = 300
    private static let silentRefreshInterval: TimeInterval = 60

    private var isFetching = false
    /// 从下拉菜单点击刷新后，数据返回时重建菜单
    private var menuRefreshPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupStatusBarView()
        statusItem.button?.action = #selector(statusBarClicked)
        statusItem.button?.target = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .appSettingsDidChange,
            object: nil
        )

        bootstrapLoginState()
        AppUpdaterManager.shared.start()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.silentRefreshInterval, repeats: true) { [weak self] _ in
            guard self?.isLoggedIn == true else { return }
            self?.refresh(silent: true)
        }
    }

    private func bootstrapLoginState() {
        if TokenStore.load() != nil {
            isLoggedIn = true
            refresh()
            return
        }

        isLoggedIn = false
        browserLoginPrompt = .needsLogin
        updateStatusBar(state: .notLoggedIn)
        attemptAutoLoginFromBrowser(silent: true)
    }

    private func setupStatusBarView() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = nil

        statusBarView = StatusBarProgressView()
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusBarView)

        NSLayoutConstraint.activate([
            statusBarView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            statusBarView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            statusBarView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            statusBarView.heightAnchor.constraint(greaterThanOrEqualToConstant: 14),
        ])
    }

    @objc private func settingsDidChange() {
        resizeStatusBar()
        if isLoggedIn, let billing = displayData.billing {
            updateStatusBar(state: .data(billing))
        } else if !isLoggedIn {
            updateStatusBar(state: .notLoggedIn)
        } else if isLoading {
            updateStatusBar(state: .loading)
        }
    }

    private func resizeStatusBar() {
        statusBarView.invalidateIntrinsicContentSize()
        statusBarView.needsLayout = true
        statusItem.length = statusBarView.intrinsicContentSize.width + 8
    }

    private func updateStatusBar(state: StatusBarState) {
        statusBarView.update(state: state)
        resizeStatusBar()
    }

    @objc private func statusBarClicked() {
        let menu = MenuBuilder.build(
            data: displayData,
            isLoggedIn: isLoggedIn,
            onRefresh: { [weak self] in self?.refreshFromMenu() },
            onOpenSettings: { [weak self] in
                self?.statusItem.menu?.cancelTracking()
                DispatchQueue.main.async {
                    self?.showSettings()
                }
            },
            onOpenDetail: { [weak self] in self?.openDetailPage() },
            onOpenBrowserLogin: { [weak self] in self?.startBrowserLoginFlow() },
            browserLoginPrompt: browserLoginPrompt,
            onCheckForUpdates: { AppUpdaterManager.shared.checkForUpdates() },
            onLogout: { [weak self] in
                self?.logout()
                // 登出后立即重建并重新弹出菜单（此时 isLoggedIn=false）
                DispatchQueue.main.async {
                    self?.statusItem.menu?.cancelTracking()
                    self?.statusBarClicked()
                }
            }
        )
        menu.delegate = self as? NSMenuDelegate
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func refreshFromMenu() {
        menuRefreshPending = true
        refresh(silent: false)
    }

    private func reopenMenuIfNeeded() {
        guard menuRefreshPending else { return }
        menuRefreshPending = false
        guard statusItem.menu != nil else { return }
        statusItem.menu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            self?.statusBarClicked()
        }
    }

    private func refresh(silent: Bool = false) {
        guard TokenStore.load() != nil else {
            isLoggedIn = false
            updateStatusBar(state: .notLoggedIn)
            return
        }
        guard !isFetching else { return }
        isFetching = true
        isLoggedIn = true
        if !silent {
            isLoading = true
            updateStatusBar(state: .loading)
        }

        let group = DispatchGroup()
        var billing: BillingData?
        var usage: UsageResponse?
        var unauthorized = false

        group.enter()
        APIClient.shared.fetchBilling { result in
            if case .success(let d) = result { billing = d }
            if case .failure(.unauthorized) = result { unauthorized = true }
            group.leave()
        }

        group.enter()
        APIClient.shared.fetchRecentUsage { result in
            if case .success(let d) = result { usage = d }
            if case .failure(.unauthorized) = result { unauthorized = true }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isFetching = false
            self.isLoading = false
            if unauthorized {
                self.menuRefreshPending = false
                self.handleUnauthorized()
                return
            }
            self.updateDisplay(billing: billing, usage: usage)
            self.reopenMenuIfNeeded()
        }
    }

    private func updateDisplay(billing: BillingData?, usage: UsageResponse?) {
        var data = DisplayData()

        if let b = billing {
            let cs = b.costSummary
            let ratioPct = (cs.usageRatio ?? (cs.used / cs.limit)) * 100
            let ratioStr = String(format: "%.2f", ratioPct)
            data.billingLines = [
                "已用: \(MenuBuilder.formatBillingCost(cs.used)) / \(MenuBuilder.formatBillingCost(cs.limit))  (\(ratioStr)%)",
                "剩余: \(MenuBuilder.formatBillingCost(cs.remaining))",
                "Token 总计: \(MenuBuilder.formatTokens(b.tokenUsage.totalTokens))",
                "输入 Token: \(MenuBuilder.formatTokens(b.tokenUsage.inputTokens))",
                "输出 Token: \(MenuBuilder.formatTokens(b.tokenUsage.outputTokens))",
            ]
            let cacheStats = b.tokenUsage.hasCacheData
                ? b.tokenUsage
                : TokenUsageDetail.aggregate(from: usage?.list ?? [])
            if cacheStats.hasCacheData {
                data.billingLines += [
                    "缓存读取: \(MenuBuilder.formatTokens(cacheStats.cacheReadTokens))",
                    "缓存写入: \(MenuBuilder.formatTokens(cacheStats.cacheWriteTokens))",
                    "缓存命中率: \(MenuBuilder.formatCacheHitRate(cacheStats.cacheHitRatePercent))",
                ]
            }
            data.billing = BillingSnapshot(ratioPct: ratioPct, remaining: cs.remaining, used: cs.used)
            updateStatusBar(state: .data(data.billing!))
        }

        let usageList = usage?.listSortedByRequestTimeDesc ?? []
        data.usageLines = usageList.map { item in
            let tok = MenuBuilder.formatTokens(item.tokenUsage?.totalTokens)
            let cost = item.costs.map { MenuBuilder.formatUsageCost($0) } ?? "-"
            return "[\(item.channelName ?? "-")] \(item.model ?? "-"): \(tok) | \(cost)"
        }
        data.usageItems = usageList.map { item in
            let name = item.model ?? "-"
            let tok = MenuBuilder.formatTokens(item.tokenUsage?.totalTokens)
            let cost = item.costs.map { MenuBuilder.formatUsageCost($0) } ?? "-"
            return UsageItem(name: name, tokens: tok, cost: cost)
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        data.lastUpdated = fmt.string(from: Date())
        displayData = data
    }

    private func startBrowserLoginFlow() {
        NSWorkspace.shared.open(AppURLs.detailPage)
        browserLoginPrompt = .waiting
        startLoginPolling()
    }

    private func startLoginPolling() {
        stopLoginPolling()
        browserLoginPrompt = .waiting

        loginPollTimer = Timer.scheduledTimer(withTimeInterval: Self.loginPollInterval, repeats: true) { [weak self] _ in
            self?.pollBrowserCookie(silent: true)
        }
        loginPollTimer?.tolerance = 0.5

        loginTimeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.loginTimeout, repeats: false) { [weak self] _ in
            self?.handleLoginPollTimeout()
        }

        pollBrowserCookie(silent: true)
    }

    private func pollBrowserCookie(silent: Bool) {
        guard !isLoggedIn, !isVerifyingLogin else {
            stopLoginPolling()
            return
        }

        CookieReaderClient.fetchToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let token):
                self.stopLoginPolling()
                self.verifyAndCompleteLogin(token: token, silent: silent)
            case .failure where silent:
                break
            case .failure(let error):
                self.updateStatusBar(state: .notLoggedIn)
                if error.needsFullDiskAccess {
                    FDAGuide.showPermissionGuide()
                } else {
                    self.showAuthAlert(title: "读取失败", message: error.localizedDescription)
                }
            }
        }
    }

    private func handleLoginPollTimeout() {
        stopLoginPolling()
        browserLoginPrompt = .timedOut
        updateStatusBar(state: .notLoggedIn)
    }

    /// Cookie 写入有延迟：验证失败后延迟重新读取并验证，最多 maxLoginRetry 次
    private func scheduleLoginRetry() {
        guard loginRetryCount < Self.maxLoginRetry else {
            loginRetryCount = 0
            TokenStore.delete()
            browserLoginPrompt = .needsLogin
            showUnauthorizedAfterRead()
            return
        }
        loginRetryCount += 1
        updateStatusBar(state: .loading)
        loginRetryTimer?.invalidate()
        loginRetryTimer = Timer.scheduledTimer(withTimeInterval: Self.loginRetryInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            // 重新读最新 Cookie + 验证
            CookieReaderClient.fetchToken { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let token):
                    self.verifyAndCompleteLogin(token: token, silent: true)
                case .failure:
                    self.scheduleLoginRetry()
                }
            }
        }
    }

    private func stopLoginPolling() {
        loginPollTimer?.invalidate()
        loginPollTimer = nil
        loginTimeoutTimer?.invalidate()
        loginTimeoutTimer = nil
        loginRetryTimer?.invalidate()
        loginRetryTimer = nil
    }

    private func attemptAutoLoginFromBrowser(silent: Bool) {
        guard !isAutoFetchingCookie, !isVerifyingLogin else { return }
        isAutoFetchingCookie = true
        updateStatusBar(state: .loading)

        CookieReaderClient.fetchToken { [weak self] result in
            guard let self else { return }
            self.isAutoFetchingCookie = false

            switch result {
            case .success(let token):
                self.verifyAndCompleteLogin(token: token, silent: silent)
            case .failure(let error):
                self.browserLoginPrompt = .needsLogin
                self.updateStatusBar(state: .notLoggedIn)
                if error.needsFullDiskAccess {
                    FDAGuide.showPermissionGuide()
                } else if !silent {
                    self.showAuthAlert(title: "读取失败", message: error.localizedDescription)
                }
            }
        }
    }

    private func verifyAndCompleteLogin(token: String, silent: Bool = false) {
        guard !isVerifyingLogin else { return }
        guard let normalized = TokenParser.parse(token) else {
            browserLoginPrompt = .needsLogin
            if !silent {
                showAuthAlert(
                    title: "登录失败",
                    message: "读取到的凭证格式无效。请在默认浏览器打开 cloud.tal.com 重新登录后再试。"
                )
            }
            return
        }
        if TokenParser.isExpired(normalized) {
            browserLoginPrompt = .needsLogin
            if !silent {
                showAuthAlert(
                    title: "登录失败",
                    message: """
                    cloud.tal.com Authorization 已过期。

                    请在默认浏览器打开 https://cloud.tal.com 重新登录后再试。
                    """
                )
            }
            return
        }
        isVerifyingLogin = true
        TokenStore.save(normalized)
        verifyBillingWithFallback(token: normalized, bearerFirst: true)
    }

    private func verifyBillingWithFallback(token: String, bearerFirst: Bool) {
        APIClient.shared.fetchBilling(bearerPrefix: bearerFirst) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                self.isVerifyingLogin = false
                self.loginRetryCount = 0
                self.finishLoginSuccess()
            case .failure(.unauthorized) where bearerFirst:
                TokenStore.save(token)
                self.verifyBillingWithFallback(token: token, bearerFirst: false)
            case .failure(.unauthorized):
                self.isVerifyingLogin = false
                // Cookie 可能刚写入还未稳定，延迟重试读取+验证
                self.scheduleLoginRetry()
            case .failure:
                self.isVerifyingLogin = false
                TokenStore.delete()
                self.browserLoginPrompt = .needsLogin
                self.showAuthAlert(
                    title: "登录失败",
                    message: "无法验证凭证，请检查网络后在浏览器重新登录并重试。"
                )
            }
        }
    }

    private func showUnauthorizedAfterRead() {
        let browser = DefaultBrowserInfo.displayName ?? "默认浏览器"
        CookieReaderClient.fetchDiagnose { [weak self] diagnose in
            guard let self else { return }
            var message = """
            已从「\(browser)」读到凭证，但 API 验证失败。

            请按顺序尝试：
            1. 关闭浏览器后重新打开，访问 https://cloud.tal.com 并重新登录
            2. 点击「在浏览器中登录」等待自动获取凭证
            """
            if !diagnose.isEmpty {
                message += "\n\n── 诊断 ──\n\(diagnose)"
            }
            self.showAuthAlert(title: "登录失败", message: message)
        }
    }

    private func finishLoginSuccess() {
        stopLoginPolling()
        browserLoginPrompt = .needsLogin
        isLoggedIn = true
        refresh()
    }

    private func handleSessionLost() {
        stopLoginPolling()
        isLoggedIn = false
        displayData = DisplayData()
        browserLoginPrompt = .needsLogin
        updateStatusBar(state: .notLoggedIn)
    }

    private func handleUnauthorized() {
        guard !isHandlingUnauthorized else { return }
        isHandlingUnauthorized = true

        TokenStore.delete()
        handleSessionLost()
        attemptAutoLoginFromBrowser(silent: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isHandlingUnauthorized = false
        }
    }

    private func logout() {
        TokenStore.delete()
        handleSessionLost()
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.showSettings()
    }

    private func openDetailPage() {
        NSWorkspace.shared.open(AppURLs.detailPage)
    }

    private func showAuthAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    @objc func openSettingsAction(_ sender: NSMenuItem) {
        (sender.representedObject as? (() -> Void))?()
    }

    @objc func openDetailAction(_ sender: NSMenuItem) {
        (sender.representedObject as? (() -> Void))?()
    }

    @objc func refreshAction(_ sender: NSMenuItem) {
        (sender.representedObject as? (() -> Void))?()
    }

    @objc func browserLoginAction(_ sender: NSMenuItem) {
        (sender.representedObject as? (() -> Void))?()
    }

    @objc func checkForUpdatesAction(_ sender: NSMenuItem) {
        (sender.representedObject as? (() -> Void))?()
    }

    @objc func logoutAction(_ sender: NSMenuItem) {
        (sender.representedObject as? (() -> Void))?()
    }
}
