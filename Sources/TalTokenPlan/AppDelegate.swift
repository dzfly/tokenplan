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

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard self?.isLoggedIn == true else { return }
            self?.refresh()
        }
    }

    private func bootstrapLoginState() {
        if TokenStore.load() != nil {
            isLoggedIn = true
            refresh()
            return
        }

        isLoggedIn = false
        updateStatusBar(state: .notLoggedIn)
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
            onRefresh: { [weak self] in self?.refresh() },
            onOpenSettings: { [weak self] in self?.showSettings() },
            onOpenDetail: { [weak self] in self?.openDetailPage() },
            onOpenBrowserLogin: { [weak self] in self?.openBrowserLogin() },
            onReadBrowserCookies: { [weak self] in self?.readFromBrowserHelper() },
            onLogout: { [weak self] in self?.logout() }
        )
        menu.delegate = self as? NSMenuDelegate
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func refresh() {
        guard TokenStore.load() != nil else {
            isLoggedIn = false
            updateStatusBar(state: .notLoggedIn)
            return
        }
        guard !isLoading else { return }
        isLoading = true
        isLoggedIn = true
        updateStatusBar(state: .loading)

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
        APIClient.shared.fetchTodayUsage { result in
            if case .success(let d) = result { usage = d }
            if case .failure(.unauthorized) = result { unauthorized = true }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            if unauthorized {
                self.handleUnauthorized()
                return
            }
            self.updateDisplay(billing: billing, usage: usage)
        }
    }

    private func updateDisplay(billing: BillingData?, usage: UsageResponse?) {
        var data = DisplayData()

        if let b = billing {
            let cs = b.costSummary
            let ratioPct = (cs.usageRatio ?? (cs.used / cs.limit)) * 100
            let ratioStr = String(format: "%.2f", ratioPct)
            data.billingLines = [
                "已用: \(MenuBuilder.formatCost(cs.used)) / \(MenuBuilder.formatCost(cs.limit))  (\(ratioStr)%)",
                "剩余: \(MenuBuilder.formatCost(cs.remaining))",
                "Token 总计: \(MenuBuilder.formatTokens(b.tokenUsage.totalTokens))",
                "输入 Token: \(MenuBuilder.formatTokens(b.tokenUsage.inputTokens))",
                "输出 Token: \(MenuBuilder.formatTokens(b.tokenUsage.outputTokens))"
            ]
            data.billing = BillingSnapshot(ratioPct: ratioPct, remaining: cs.remaining)
            updateStatusBar(state: .data(data.billing!))
        }

        data.usageLines = (usage?.list ?? []).map { item in
            let tok = MenuBuilder.formatTokens(item.tokenUsage?.totalTokens)
            let cost = item.costs.map { String(format: "¥%.4f", $0) } ?? "-"
            return "[\(item.channelName ?? "-")] \(item.model ?? "-"): \(tok) | \(cost)"
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        data.lastUpdated = fmt.string(from: Date())
        displayData = data
    }

    private func openBrowserLogin() {
        NSWorkspace.shared.open(AppURLs.detailPage)
    }

    private func readFromBrowserHelper() {
        updateStatusBar(state: .loading)

        CookieReaderClient.fetchToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let token):
                self.verifyAndCompleteLogin(token: token)
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

    private func verifyAndCompleteLogin(token: String) {
        guard !isVerifyingLogin else { return }
        guard let normalized = TokenParser.parse(token) else {
            showAuthAlert(
                title: "登录失败",
                message: "读取到的凭证格式无效。请在默认浏览器打开 cloud.tal.com 重新登录后再试。"
            )
            return
        }
        if TokenParser.isExpired(normalized) {
            showAuthAlert(
                title: "登录失败",
                message: """
                cloud.tal.com Authorization 已过期。

                请在默认浏览器打开 https://cloud.tal.com 重新登录后再试。
                """
            )
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
                self.finishLoginSuccess()
            case .failure(.unauthorized) where bearerFirst:
                TokenStore.save(token)
                self.verifyBillingWithFallback(token: token, bearerFirst: false)
            case .failure(.unauthorized):
                self.isVerifyingLogin = false
                TokenStore.delete()
                self.showUnauthorizedAfterRead()
            case .failure:
                self.isVerifyingLogin = false
                TokenStore.delete()
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
            2. 再点击「从浏览器读取凭证」
            """
            if !diagnose.isEmpty {
                message += "\n\n── 诊断 ──\n\(diagnose)"
            }
            self.showAuthAlert(title: "登录失败", message: message)
        }
    }

    private func finishLoginSuccess() {
        isLoggedIn = true
        refresh()
    }

    private func handleSessionLost() {
        isLoggedIn = false
        displayData = DisplayData()
        updateStatusBar(state: .notLoggedIn)
    }

    private func handleUnauthorized() {
        guard !isHandlingUnauthorized else { return }
        isHandlingUnauthorized = true

        TokenStore.delete()
        handleSessionLost()

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

    @objc func readBrowserCookiesAction(_ sender: NSMenuItem) {
        (sender.representedObject as? (() -> Void))?()
    }

    @objc func browserLoginAction(_ sender: NSMenuItem) {
        (sender.representedObject as? (() -> Void))?()
    }

    @objc func logoutAction(_ sender: NSMenuItem) {
        (sender.representedObject as? (() -> Void))?()
    }
}
