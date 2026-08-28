import AppKit
import ObjectiveC

struct DisplayData {
    var billing: BillingSnapshot?
    var todayTokens: String = ""
    var todayCost: String = ""
    var lastUpdated: String = ""
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

/// 菜单内图标按钮；keepsMenuOpen 为 true 时不关闭下拉菜单
private final class MenuIconButton: NSButton {
    var keepsMenuOpen = false

    private static let spinKey = "refreshSpin"
    private static let rotationDuration: CFTimeInterval = 0.45
    private var spinStartedAt: Date?

    override func mouseDown(with event: NSEvent) {
        if keepsMenuOpen {
            guard let target, let action else { return }
            NSApp.sendAction(action, to: target, from: self)
            return
        }
        super.mouseDown(with: event)
    }

    func startSpinning() {
        spinStartedAt = Date()
        wantsLayer = true
        layoutSubtreeIfNeeded()
        configureRotationCenter()
        guard let layer, layer.animation(forKey: Self.spinKey) == nil else { return }

        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = -2 * Double.pi
        animation.duration = Self.rotationDuration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: Self.spinKey)
    }

    override func layout() {
        super.layout()
        if wantsLayer, layer?.animation(forKey: Self.spinKey) != nil {
            configureRotationCenter()
        }
    }

    private func configureRotationCenter() {
        guard let layer, let superview else { return }
        let centerInSuperview = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: superview)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: centerInSuperview.x, y: centerInSuperview.y)
    }

    func stopSpinning(minRotations: Double, completion: @escaping () -> Void) {
        let start = spinStartedAt ?? Date()
        let minDuration = minRotations * Self.rotationDuration
        let delay = max(0, minDuration - Date().timeIntervalSince(start))

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                completion()
                return
            }
            self.layer?.removeAnimation(forKey: Self.spinKey)
            self.layer?.transform = CATransform3DIdentity
            self.spinStartedAt = nil
            completion()
        }
    }
}

/// 持有按钮闭包，作为 NSButton target
final class MenuActionHost: NSObject {
    enum Action: Int {
        case refresh = 0
        case settings = 1
        case openMain = 2
        case browserLogin = 3
        case checkUpdates = 4
        case logout = 5
        case quit = 6
    }

    private var handlers: [Action: () -> Void] = [:]
    fileprivate weak var refreshButton: MenuIconButton?
    private var isRefreshSpinning = false

    func set(_ action: Action, handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    func beginRefreshSpin() {
        isRefreshSpinning = true
        refreshButton?.startSpinning()
    }

    func endRefreshSpin(minRotations: Double, completion: @escaping () -> Void) {
        guard isRefreshSpinning else {
            completion()
            return
        }
        isRefreshSpinning = false
        guard let refreshButton else {
            completion()
            return
        }
        refreshButton.stopSpinning(minRotations: minRotations, completion: completion)
    }

    @objc func dispatch(_ sender: NSButton) {
        guard let action = Action(rawValue: sender.tag) else { return }
        if action == .refresh, let btn = sender as? MenuIconButton {
            refreshButton = btn
        }
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

        static let hint = NSColor(name: "TokenPlanMenuHint") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.52)
                : NSColor(white: 0.0, alpha: 0.42)
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

        static func hint(_ text: String) -> NSAttributedString {
            attributed(text, font: .systemFont(ofSize: NSFont.systemFontSize, weight: .regular), color: MenuText.hint)
        }

        private static func attributed(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
    }

    // MARK: - Card container

    private static let cardWidth: CGFloat = 300
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
    private static func cardItem(
        rows: [CardRow],
        cardInsetX insetX: CGFloat = cardInsetX,
        contentInsetX contentX: CGFloat = contentInsetX,
        rowSpacing spacing: CGFloat = rowSpacing
    ) -> NSMenuItem {
        let contentWidth = cardWidth - insetX * 2 - contentX * 2
        let contentHeight = rows.reduce(0) { $0 + $1.height }
            + spacing * CGFloat(max(0, rows.count - 1))
        let cardHeight = contentHeight + contentInsetTop + contentInsetBottom
        let wrapperHeight = cardHeight + cardInsetY * 2

        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: wrapperHeight))
        let card = NSView(frame: NSRect(x: insetX, y: cardInsetY,
                                        width: cardWidth - insetX * 2,
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
            let rowFrame = NSRect(x: contentX, y: y, width: contentWidth, height: row.height)
            row.view.frame = rowFrame
            row.layout?(rowFrame)
            card.addSubview(row.view)
            y -= spacing
        }

        let item = NSMenuItem()
        item.view = wrapper
        return item
    }

    private struct HeaderIconButton {
        var action: MenuActionHost.Action
        var symbolName: String
        var accessibilityDesc: String
        var keepsMenuOpen: Bool = false
    }

    /// 卡片外的标题 + 右侧图标按钮（独立 menu item view）
    private static func headerWithIconButton(
        _ text: String,
        host: MenuActionHost,
        buttons: [HeaderIconButton],
        horizontalInset: CGFloat = 14
    ) -> NSMenuItem {
        let label = NSTextField(labelWithAttributedString: Style.title(text))
        label.sizeToFit()

        var iconButtons: [NSButton] = []
        for button in buttons {
            let btn = MenuIconButton()
            btn.keepsMenuOpen = button.keepsMenuOpen
            btn.isBordered = false
            btn.bezelStyle = .inline
            btn.image = NSImage(systemSymbolName: button.symbolName, accessibilityDescription: button.accessibilityDesc)
            btn.imagePosition = .imageOnly
            btn.contentTintColor = MenuText.caption
            btn.tag = button.action.rawValue
            btn.target = host
            btn.action = #selector(MenuActionHost.dispatch(_:))
            btn.sizeToFit()
            if button.action == .refresh {
                host.refreshButton = btn
            }
            iconButtons.append(btn)
        }

        let labelH = label.fittingSize.height
        let btnH = iconButtons.map(\.fittingSize.height).max() ?? 18
        let height = max(labelH, btnH, 18) + 2
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: height))

        var trailingX = cardWidth - horizontalInset
        for btn in iconButtons.reversed() {
            let fit = btn.fittingSize
            let btnSize = max(max(fit.width, fit.height), 18)
            trailingX -= btnSize
            btn.frame = NSRect(x: trailingX, y: (height - btnSize) / 2, width: btnSize, height: btnSize)
            wrapper.addSubview(btn)
            trailingX -= 6
        }

        label.frame = NSRect(x: horizontalInset, y: (height - labelH) / 2, width: max(0, trailingX - horizontalInset), height: labelH)
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

    private static func actionButtonTitle(title: String, symbolName: String?, hintStyle: Bool = false) -> NSAttributedString {
        let textColor = hintStyle ? MenuText.hint : MenuText.primary
        let fontWeight: NSFont.Weight = hintStyle ? .regular : .medium
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: fontWeight),
            .foregroundColor: textColor,
        ]
        guard let symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        else {
            return hintStyle ? Style.hint(title) : Style.action(title)
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
        enabled: Bool = true,
        hintStyle: Bool = false
    ) -> CardRow {
        let btn = NSButton()
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.layer?.cornerCurve = .continuous
        btn.bezelStyle = .inline
        btn.attributedTitle = actionButtonTitle(title: title, symbolName: symbolName, hintStyle: hintStyle)
        btn.contentTintColor = hintStyle ? MenuText.hint : nil
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

    // MARK: - Build

    static func build(
        data: DisplayData,
        isLoggedIn: Bool,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenMain: @escaping () -> Void,
        onOpenBrowserLogin: @escaping () -> Void,
        browserLoginPrompt: BrowserLoginPrompt,
        onCheckForUpdates: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        populate(
            menu,
            data: data,
            isLoggedIn: isLoggedIn,
            onRefresh: onRefresh,
            onOpenSettings: onOpenSettings,
            onOpenMain: onOpenMain,
            onOpenBrowserLogin: onOpenBrowserLogin,
            browserLoginPrompt: browserLoginPrompt,
            onCheckForUpdates: onCheckForUpdates,
            onLogout: onLogout
        )
        return menu
    }

    /// 刷新已打开的下拉菜单内容，不关闭菜单
    static func rebuild(
        _ menu: NSMenu,
        data: DisplayData,
        isLoggedIn: Bool,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenMain: @escaping () -> Void,
        onOpenBrowserLogin: @escaping () -> Void,
        browserLoginPrompt: BrowserLoginPrompt,
        onCheckForUpdates: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        populate(
            menu,
            data: data,
            isLoggedIn: isLoggedIn,
            onRefresh: onRefresh,
            onOpenSettings: onOpenSettings,
            onOpenMain: onOpenMain,
            onOpenBrowserLogin: onOpenBrowserLogin,
            browserLoginPrompt: browserLoginPrompt,
            onCheckForUpdates: onCheckForUpdates,
            onLogout: onLogout
        )
        menu.update()
    }

    private static func populate(
        _ menu: NSMenu,
        data: DisplayData,
        isLoggedIn: Bool,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenMain: @escaping () -> Void,
        onOpenBrowserLogin: @escaping () -> Void,
        browserLoginPrompt: BrowserLoginPrompt,
        onCheckForUpdates: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let host = MenuActionHost()
        host.set(.refresh, handler: onRefresh)
        host.set(.settings, handler: onOpenSettings)
        host.set(.openMain, handler: onOpenMain)
        host.set(.browserLogin, handler: onOpenBrowserLogin)
        host.set(.checkUpdates, handler: onCheckForUpdates)
        host.set(.logout, handler: onLogout)
        host.set(.quit, handler: { NSApp.terminate(nil) })
        objc_setAssociatedObject(menu, &hostKey, host, .OBJC_ASSOCIATION_RETAIN)

        if isLoggedIn {
            menu.addItem(headerWithIconButton("账单概览", host: host, buttons: [
                HeaderIconButton(action: .refresh, symbolName: "arrow.clockwise", accessibilityDesc: "刷新", keepsMenuOpen: true),
            ]))
            var rows: [CardRow] = []
            if let b = data.billing {
                rows.append(dataRow("已用: \(MenuBuilder.formatBillingCost(b.used)) / \(MenuBuilder.formatBillingCost(b.limit))（\(String(format: "%.1f", b.ratioPct))%）"))
                rows.append(progressRow(ratio: b.ratioPct / 100, color: .controlAccentColor))
                rows.append(dataRow("剩余: \(MenuBuilder.formatBillingCost(b.remaining))"))
                if let maxUsed = b.maxModelUsed, let maxLimit = b.maxModelLimit {
                    let pctText = b.maxModelRatioPct.map { String(format: "%.1f", $0) } ?? "-"
                    rows.append(dataRow("Max: \(MenuBuilder.formatBillingCost(maxUsed)) / \(MenuBuilder.formatBillingCost(maxLimit))（\(pctText)%）"))
                    if let maxRemaining = b.maxModelRemaining {
                        rows.append(dataRow("Max 剩余: \(MenuBuilder.formatBillingCost(maxRemaining))"))
                    }
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
                buttonRow(title: "主界面", symbolName: "macwindow", action: .openMain, host: host),
                separatorRow(),
                buttonRow(title: "设置", symbolName: "gearshape", action: .settings, host: host),
                separatorRow(),
                buttonRow(title: "退出", symbolName: "power", action: .quit, host: host),
            ]))

            if !data.lastUpdated.isEmpty {
                menu.addItem(hintItem("上次更新: \(data.lastUpdated)"))
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
    }

    /// 底部提示文字行（view-based）：attributedTitle 菜单项在菜单展开中重建时
    /// 动态色会按系统明暗（而非菜单外观）解析，导致深色菜单下文字变黑
    private static func hintItem(_ text: String) -> NSMenuItem {
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: 18))
        let label = NSTextField(labelWithAttributedString: Style.hint(text))
        label.sizeToFit()
        label.frame = NSRect(
            x: 14,
            y: (wrapper.frame.height - label.frame.height) / 2,
            width: cardWidth - 28,
            height: label.frame.height
        )
        wrapper.addSubview(label)
        let item = NSMenuItem()
        item.view = wrapper
        item.isEnabled = false
        return item
    }

    private static func spacerItem(height: CGFloat) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: height))
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        return item
    }

    // AppDelegate 旧 selector 路由保留兼容（不再由菜单调用，但保留方法签名）
    static func formatTokens(_ n: Int64?) -> String {
        guard let n = n else { return "-" }
        if n >= 100_000_000 { return String(format: "%.2f亿", Double(n) / 100_000_000) }
        if n >= 10_000 { return String(format: "%.2f万", Double(n) / 10_000) }
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

    static func actionHost(for menu: NSMenu?) -> MenuActionHost? {
        guard let menu else { return nil }
        return objc_getAssociatedObject(menu, &hostKey) as? MenuActionHost
    }
}

private var hostKey: UInt8 = 0