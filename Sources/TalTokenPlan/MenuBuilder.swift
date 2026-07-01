import AppKit
import ObjectiveC

struct UsageItem {
    var name: String
    var tokens: String
    var cost: String
}

struct DisplayData {
    var billingLines: [String] = []
    var usageLines: [String] = []
    var usageItems: [UsageItem] = []
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

/// 持有按钮闭包，作为 NSButton target
final class MenuActionHost: NSObject {
    enum Action: Int {
        case refresh = 0
        case settings = 1
        case detail = 2
        case browserLogin = 3
        case checkUpdates = 4
        case logout = 5
        case quit = 6
    }

    private var handlers: [Action: () -> Void] = [:]

    func set(_ action: Action, handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    @objc func dispatch(_ sender: NSButton) {
        guard let action = Action(rawValue: sender.tag) else { return }
        handlers[action]?()
    }
}

enum MenuBuilder {
    private enum MenuText {
        static let primary = NSColor(name: "TokenPlanMenuPrimary") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 1.0)
                : NSColor(white: 0.0, alpha: 1.0)
        }

        static let cardDataRow = NSColor(name: "TokenPlanMenuCardDataRow") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.62)
                : NSColor(white: 0.0, alpha: 0.62)
        }

        static let cardAccent = NSColor(name: "TokenPlanMenuCardAccent") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.72)
                : NSColor(white: 0.0, alpha: 0.72)
        }

        static let caption = NSColor(name: "TokenPlanMenuCaption") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.72, alpha: 1.0)
                : NSColor(white: 0.22, alpha: 1.0)
        }

        static let accent = NSColor(name: "TokenPlanMenuAccent") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.16, alpha: 1.0)
                : NSColor(calibratedRed: 0.90, green: 0.46, blue: 0.05, alpha: 1.0)
        }
    }

    private enum Style {
        static func title(_ text: String) -> NSAttributedString {
            attributed(text, font: .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold), color: MenuText.caption)
        }

        static func dataRow(_ text: String) -> NSAttributedString {
            attributed(text, font: .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular), color: MenuText.cardDataRow)
        }

        static func caption(_ text: String) -> NSAttributedString {
            attributed(text, font: .systemFont(ofSize: NSFont.smallSystemFontSize), color: MenuText.caption)
        }

        static func action(_ text: String) -> NSAttributedString {
            attributed(text, font: .systemFont(ofSize: NSFont.systemFontSize, weight: .medium), color: MenuText.primary)
        }

        private static func attributed(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
    }

    // MARK: - Card container

    private static let cardWidth: CGFloat = 280
    private static let cardInsetX: CGFloat = 10
    private static let cardInsetY: CGFloat = 2
    private static let contentInsetX: CGFloat = 14
    private static let contentInsetTop: CGFloat = 10
    private static let contentInsetBottom: CGFloat = 10
    private static let rowSpacing: CGFloat = 4

    /// 卡片内一行内容：view + 高度 + 行内布局闭包（行 frame 设好后调用，行内可摆子视图）
    private final class CardRow {
        let view: NSView
        let height: CGFloat
        let layout: ((NSRect) -> Void)?
        init(view: NSView, height: CGFloat, layout: ((NSRect) -> Void)? = nil) {
            self.view = view
            self.height = height
            self.layout = layout
        }
    }

    private static func cardBackgroundColor(appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(white: 0.0, alpha: 0.04)
    }

    private static func cardBorderColor(appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(white: 1.0, alpha: 0.12)
            : NSColor(white: 0.0, alpha: 0.08)
    }

    /// 构建一张卡片 NSMenuItem：自上而下布局，数组顺序与视觉顺序一致
    private static func cardItem(rows: [CardRow]) -> NSMenuItem {
        let contentWidth = cardWidth - cardInsetX * 2 - contentInsetX * 2
        let contentHeight = rows.reduce(0) { $0 + $1.height }
            + rowSpacing * CGFloat(max(0, rows.count - 1))
        let cardHeight = contentHeight + contentInsetTop + contentInsetBottom
        let wrapperHeight = cardHeight + cardInsetY * 2

        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: wrapperHeight))
        let card = NSView(frame: NSRect(x: cardInsetX, y: cardInsetY,
                                        width: cardWidth - cardInsetX * 2,
                                        height: cardHeight))
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        let appearance = NSApp.effectiveAppearance
        card.layer?.backgroundColor = cardBackgroundColor(appearance: appearance).cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = cardBorderColor(appearance: appearance).cgColor
        wrapper.addSubview(card)

        var y = cardHeight - contentInsetTop
        for row in rows {
            y -= row.height
            let rowFrame = NSRect(x: contentInsetX, y: y, width: contentWidth, height: row.height)
            row.view.frame = rowFrame
            row.layout?(rowFrame)
            card.addSubview(row.view)
            y -= rowSpacing
        }

        let item = NSMenuItem()
        item.view = wrapper
        return item
    }

    /// 卡片外的标题项（浅色小字，置于卡片上方）
    private static func headerItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = Style.title(text)
        item.isEnabled = false
        return item
    }

    /// 卡片外的标题 + 右侧图标按钮（独立 menu item view）
    private static func headerWithIconButton(
        _ text: String,
        host: MenuActionHost,
        buttons: [(action: MenuActionHost.Action, symbolName: String, accessibilityDesc: String)]
    ) -> NSMenuItem {
        let label = NSTextField(labelWithAttributedString: Style.title(text))
        label.sizeToFit()

        var iconButtons: [NSButton] = []
        for button in buttons {
            let btn = NSButton()
            btn.isBordered = false
            btn.bezelStyle = .inline
            btn.image = NSImage(systemSymbolName: button.symbolName, accessibilityDescription: button.accessibilityDesc)
            btn.imagePosition = .imageOnly
            btn.contentTintColor = MenuText.caption
            btn.tag = button.action.rawValue
            btn.target = host
            btn.action = #selector(MenuActionHost.dispatch(_:))
            btn.sizeToFit()
            iconButtons.append(btn)
        }

        let labelH = label.fittingSize.height
        let btnH = iconButtons.map(\.fittingSize.height).max() ?? 18
        let height = max(labelH, btnH, 18) + 2
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: height))

        var trailingX = cardWidth - 14.0
        for btn in iconButtons.reversed() {
            let btnW = btn.fittingSize.width
            trailingX -= btnW
            btn.frame = NSRect(x: trailingX, y: (height - btnH) / 2, width: btnW, height: btnH)
            wrapper.addSubview(btn)
            trailingX -= 6
        }

        label.frame = NSRect(x: 14, y: (height - labelH) / 2, width: max(0, trailingX - 14), height: labelH)
        wrapper.addSubview(label)

        let item = NSMenuItem()
        item.view = wrapper
        return item
    }

    private static func dataRow(_ text: String) -> CardRow {
        let label = NSTextField(labelWithAttributedString: Style.dataRow(text))
        label.sizeToFit()
        let h = max(label.fittingSize.height, 18)
        return CardRow(view: label, height: h)
    }

    private static let actionIconWidth: CGFloat = 16
    private static let actionIconSpacing: CGFloat = 6

    private static func actionButtonTitle(title: String, symbolName: String?) -> NSAttributedString {
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .foregroundColor: MenuText.primary,
        ]
        guard let symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        else {
            return Style.action(title)
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -3, width: actionIconWidth, height: actionIconWidth)

        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: String(repeating: " ", count: Int(actionIconSpacing / 3)), attributes: textAttrs))
        result.append(NSAttributedString(string: title, attributes: textAttrs))
        return result
    }

    private static func buttonRow(
        title: String,
        symbolName: String? = nil,
        action: MenuActionHost.Action,
        host: MenuActionHost,
        enabled: Bool = true
    ) -> CardRow {
        let btn = NSButton()
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.layer?.cornerCurve = .continuous
        btn.bezelStyle = .inline
        btn.attributedTitle = actionButtonTitle(title: title, symbolName: symbolName)
        btn.alignment = .left
        btn.imagePosition = .noImage
        btn.tag = action.rawValue
        btn.target = host
        btn.action = #selector(MenuActionHost.dispatch(_:))
        btn.isEnabled = enabled
        btn.sizeToFit()

        let height = max(btn.fittingSize.height + 6, 28)
        return CardRow(view: btn, height: height)
    }

    /// 卡片内分隔线行
    private static func separatorRow() -> CardRow {
        let line = NSBox()
        line.boxType = .separator
        return CardRow(view: line, height: 1)
    }

    /// 顶部图标按钮（独立 menu item，icon-only）
    /// 用量行：左名称（可截断）+ 右金额（始终可见）
    private static func usageRow(name: String, tokens: String, cost: String) -> CardRow {
        let container = NSView()
        let nameField = NSTextField(labelWithString: "\(name)  \(tokens)")
        nameField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        nameField.textColor = MenuText.cardDataRow
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.sizeToFit()

        let costField = NSTextField(labelWithString: cost)
        costField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        costField.textColor = MenuText.cardAccent
        costField.sizeToFit()

        container.addSubview(nameField)
        container.addSubview(costField)
        return CardRow(view: container, height: max(nameField.fittingSize.height, 18)) { frame in
            let costW = costField.fittingSize.width
            nameField.frame = NSRect(x: 0, y: (frame.height - nameField.fittingSize.height) / 2,
                                     width: frame.width - costW - 8, height: nameField.fittingSize.height)
            costField.frame = NSRect(x: frame.width - costW, y: (frame.height - costField.fittingSize.height) / 2,
                                     width: costW, height: costField.fittingSize.height)
        }
    }

    /// 标题行 + 右侧详情图标按钮（用量明细区域用）
    // MARK: - Build

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
        let host = MenuActionHost()
        host.set(.refresh, handler: onRefresh)
        host.set(.settings, handler: onOpenSettings)
        host.set(.detail, handler: onOpenDetail)
        host.set(.browserLogin, handler: onOpenBrowserLogin)
        host.set(.checkUpdates, handler: onCheckForUpdates)
        host.set(.logout, handler: onLogout)
        host.set(.quit, handler: { NSApp.terminate(nil) })
        objc_setAssociatedObject(menu, &hostKey, host, .OBJC_ASSOCIATION_RETAIN)

        if isLoggedIn {
            // 卡片1：账单总览（标题在卡片外，右侧刷新图标按钮）
            menu.addItem(headerWithIconButton("账单总览", host: host, buttons: [
                (.refresh, "arrow.clockwise", "刷新"),
            ]))
            var rows: [CardRow] = []
            for line in data.billingLines { rows.append(dataRow(line)) }
            menu.addItem(cardItem(rows: rows))

            // 卡片2：用量明细（标题+详情图标在卡片外，卡片内只放用量行）
            if !data.usageItems.isEmpty {
                menu.addItem(spacerItem(height: 6))
                menu.addItem(headerWithIconButton("用量明细", host: host, buttons: [
                    (.detail, "arrow.up.forward.square", "查看详情"),
                ]))
                var usageRows: [CardRow] = []
                for item in data.usageItems {
                    usageRows.append(usageRow(name: item.name, tokens: item.tokens, cost: item.cost))
                }
                menu.addItem(cardItem(rows: usageRows))
            }

            // 操作按钮：设置 + 退出
            menu.addItem(spacerItem(height: 6))
            menu.addItem(cardItem(rows: [
                buttonRow(title: "设置", symbolName: "gearshape", action: .settings, host: host),
                separatorRow(),
                buttonRow(title: "退出", symbolName: "power", action: .quit, host: host),
            ]))

            if !data.lastUpdated.isEmpty {
                let cap = NSMenuItem()
                cap.attributedTitle = Style.caption("更新: \(data.lastUpdated)")
                cap.isEnabled = false
                menu.addItem(cap)
            }
        } else {
            menu.addItem(cardItem(rows: [dataRow("未检测到登录凭证")]))

            menu.addItem(spacerItem(height: 6))
            menu.addItem(cardItem(rows: [
                buttonRow(title: browserLoginPrompt.menuTitle, action: .browserLogin, host: host,
                          enabled: browserLoginPrompt != .waiting),
            ]))

            menu.addItem(spacerItem(height: 6))
            menu.addItem(cardItem(rows: [
                buttonRow(title: "设置", symbolName: "gearshape", action: .settings, host: host),
                separatorRow(),
                buttonRow(title: "退出", symbolName: "power", action: .quit, host: host),
            ]))
        }

        return menu
    }

    private static func spacerItem(height: CGFloat) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: height))
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        return item
    }

    // AppDelegate 旧 selector 路由保留兼容（不再由菜单调用，但保留方法签名）
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

    static func formatCacheHitRate(_ percent: Double?) -> String {
        guard let percent else { return "-" }
        return String(format: "%.2f%%", percent)
    }
}

private var hostKey: UInt8 = 0