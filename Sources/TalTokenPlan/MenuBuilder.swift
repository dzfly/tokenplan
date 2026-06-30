import AppKit

struct DisplayData {
    var billingLines: [String] = []
    var usageLines: [String] = []
    var lastUpdated: String = ""
    var billing: BillingSnapshot?
}

enum AppURLs {
    static let detailPage = URL(string: "https://cloud.tal.com/ai/tokenPlan/costStatistics")!
}

enum MenuBuilder {
    static func build(
        data: DisplayData,
        isLoggedIn: Bool,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenDetail: @escaping () -> Void,
        onOpenBrowserLogin: @escaping () -> Void,
        onReadBrowserCookies: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()

        if isLoggedIn {
            let titleItem = NSMenuItem(title: "📊 账单总览", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            for line in data.billingLines {
                let item = NSMenuItem(title: "  \(line)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }

            if !data.usageLines.isEmpty {
                menu.addItem(.separator())
                let usageTitle = NSMenuItem(title: "📈 今日用量 (Top5)", action: nil, keyEquivalent: "")
                usageTitle.isEnabled = false
                menu.addItem(usageTitle)
                for line in data.usageLines {
                    let item = NSMenuItem(title: "  \(line)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                }
            }
        } else {
            let hint = NSMenuItem(title: "未登录，请先在浏览器登录", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "⚙️ 设置", action: #selector(AppDelegate.openSettingsAction(_:)), keyEquivalent: ",")
        settingsItem.representedObject = onOpenSettings as AnyObject
        menu.addItem(settingsItem)

        if isLoggedIn {
            let detailItem = NSMenuItem(title: "🌐 查看详情", action: #selector(AppDelegate.openDetailAction(_:)), keyEquivalent: "")
            detailItem.representedObject = onOpenDetail as AnyObject
            menu.addItem(detailItem)
        }

        if isLoggedIn, !data.lastUpdated.isEmpty {
            let updItem = NSMenuItem(title: "更新: \(data.lastUpdated)", action: nil, keyEquivalent: "")
            updItem.isEnabled = false
            menu.addItem(updItem)
        }

        if isLoggedIn {
            let refreshItem = NSMenuItem(title: "🔄 刷新", action: #selector(AppDelegate.refreshAction(_:)), keyEquivalent: "r")
            refreshItem.representedObject = onRefresh as AnyObject
            menu.addItem(refreshItem)
        }

        menu.addItem(.separator())

        if !isLoggedIn {
            let readItem = NSMenuItem(title: "🔑 从浏览器读取凭证", action: #selector(AppDelegate.readBrowserCookiesAction(_:)), keyEquivalent: "")
            readItem.representedObject = onReadBrowserCookies as AnyObject
            menu.addItem(readItem)

            let browserItem = NSMenuItem(title: "🌐 在浏览器中登录", action: #selector(AppDelegate.browserLoginAction(_:)), keyEquivalent: "")
            browserItem.representedObject = onOpenBrowserLogin as AnyObject
            menu.addItem(browserItem)
        }

        if isLoggedIn {
            let logoutItem = NSMenuItem(title: "🚪 登出", action: #selector(AppDelegate.logoutAction(_:)), keyEquivalent: "")
            logoutItem.representedObject = onLogout as AnyObject
            menu.addItem(logoutItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    static func formatTokens(_ n: Int64?) -> String {
        guard let n = n else { return "-" }
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000    { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    static func formatCost(_ v: Double?) -> String {
        guard let v = v else { return "-" }
        return String(format: "¥%.4f", v)
    }
}
