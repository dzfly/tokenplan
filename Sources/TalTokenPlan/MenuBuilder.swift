import AppKit

struct DisplayData {
    var billingLines: [String] = []
    var usageLines: [String] = []
    var lastUpdated: String = ""
    var billing: BillingSnapshot?
}

enum BrowserLoginPrompt {
    case needsLogin
    case waiting
    case timedOut

    var menuTitle: String {
        switch self {
        case .needsLogin: return "🌐 在浏览器中登录"
        case .waiting: return "⏳ 等待浏览器登录…"
        case .timedOut: return "获取登录信息超时，重新登录"
        }
    }
}

enum AppURLs {
    static let detailPage = URL(string: "https://cloud.tal.com/ai/tokenPlan/costStatistics")!
}

enum MenuBuilder {
    private enum MenuText {
        /// 菜单背景上高对比度主色（浅色模式纯黑，深色模式纯白）
        static let primary = NSColor(name: "TokenPlanMenuPrimary") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 1.0)
                : NSColor(white: 0.0, alpha: 1.0)
        }

        static let dataRow = NSColor(name: "TokenPlanMenuDataRow") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.6)
                : NSColor(white: 0.0, alpha: 0.6)
        }

        static let caption = NSColor(name: "TokenPlanMenuCaption") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.72, alpha: 1.0)
                : NSColor(white: 0.22, alpha: 1.0)
        }
    }

    private enum Style {
        static func action(_ text: String) -> NSAttributedString {
            attributed(text, font: .systemFont(ofSize: NSFont.systemFontSize, weight: .medium), color: MenuText.primary)
        }

        static func title(_ text: String) -> NSAttributedString {
            attributed(text, font: .boldSystemFont(ofSize: NSFont.systemFontSize), color: MenuText.primary)
        }

        static func body(_ text: String) -> NSAttributedString {
            attributed("  \(text)", font: .systemFont(ofSize: NSFont.systemFontSize, weight: .medium), color: MenuText.dataRow)
        }

        static func caption(_ text: String) -> NSAttributedString {
            attributed(text, font: .systemFont(ofSize: NSFont.smallSystemFontSize), color: MenuText.caption)
        }

        static func hint(_ text: String) -> NSAttributedString {
            attributed(text, font: .systemFont(ofSize: NSFont.systemFontSize, weight: .medium), color: MenuText.primary)
        }

        private static func attributed(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
    }

    /// 用自定义 view 渲染，避免 NSMenu 淡化 attributedTitle 颜色
    private static func infoItem(
        _ text: String,
        font: NSFont,
        color: NSColor,
        leading: CGFloat = 18
    ) -> NSMenuItem {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leading),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private static func infoItem(_ title: String, style: (String) -> NSAttributedString) -> NSMenuItem {
        let attr = style(title)
        let text = attr.string
        let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? .menuFont(ofSize: NSFont.systemFontSize)
        let color = attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor ?? MenuText.primary
        let leading: CGFloat = text.hasPrefix("  ") ? 22 : 18
        return infoItem(text, font: font, color: color, leading: leading)
    }

    private static func infoItem(_ title: String) -> NSMenuItem {
        infoItem(title, style: Style.body)
    }

    private static func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = Style.action(title)
        item.action = action
        item.keyEquivalent = keyEquivalent
        item.representedObject = handler as AnyObject
        return item
    }

    static func build(
        data: DisplayData,
        isLoggedIn: Bool,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenDetail: @escaping () -> Void,
        onOpenBrowserLogin: @escaping () -> Void,
        browserLoginPrompt: BrowserLoginPrompt,
        onCheckForUpdates: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()

        if isLoggedIn {
            menu.addItem(infoItem("📊 账单总览", style: Style.title))
            for line in data.billingLines {
                menu.addItem(infoItem(line))
            }

            if !data.usageLines.isEmpty {
                menu.addItem(.separator())
                menu.addItem(infoItem("📈 今日用量 (Top5)", style: Style.title))
                for line in data.usageLines {
                    menu.addItem(infoItem(line))
                }
            }
        } else {
            menu.addItem(infoItem("未检测到登录凭证", style: Style.hint))
        }

        menu.addItem(.separator())

        menu.addItem(actionItem(title: "⚙️ 设置", action: #selector(AppDelegate.openSettingsAction(_:)), keyEquivalent: ",", handler: onOpenSettings))

        if isLoggedIn {
            menu.addItem(actionItem(title: "🌐 查看详情", action: #selector(AppDelegate.openDetailAction(_:)), keyEquivalent: "", handler: onOpenDetail))
        }

        if isLoggedIn, !data.lastUpdated.isEmpty {
            menu.addItem(infoItem("更新: \(data.lastUpdated)", style: Style.caption))
        }

        if isLoggedIn {
            menu.addItem(actionItem(title: "🔄 刷新", action: #selector(AppDelegate.refreshAction(_:)), keyEquivalent: "r", handler: onRefresh))
        }

        menu.addItem(.separator())

        if !isLoggedIn {
            let loginItem = actionItem(
                title: browserLoginPrompt.menuTitle,
                action: #selector(AppDelegate.browserLoginAction(_:)),
                keyEquivalent: "",
                handler: onOpenBrowserLogin
            )
            loginItem.isEnabled = browserLoginPrompt != .waiting
            menu.addItem(loginItem)
        }

        if isLoggedIn {
            menu.addItem(actionItem(title: "🚪 登出", action: #selector(AppDelegate.logoutAction(_:)), keyEquivalent: "", handler: onLogout))
        }

        menu.addItem(.separator())

        menu.addItem(actionItem(title: "⬆️ 检查更新…", action: #selector(AppDelegate.checkForUpdatesAction(_:)), keyEquivalent: "", handler: onCheckForUpdates))

        menu.addItem(.separator())
        let quitItem = NSMenuItem()
        quitItem.attributedTitle = Style.action("退出")
        quitItem.action = #selector(NSApplication.terminate(_:))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)

        return menu
    }

    static func formatTokens(_ n: Int64?) -> String {
        guard let n = n else { return "-" }
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000    { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    static func formatBillingCost(_ v: Double?) -> String {
        guard let v = v else { return "-" }
        return String(format: "¥%.1f", v)
    }

    static func formatUsageCost(_ v: Double?) -> String {
        guard let v = v else { return "-" }
        return String(format: "¥%.4f", v)
    }
}
