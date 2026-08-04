import AppKit
import ObjectiveC

struct UsageItem {
    var time: String
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
    var todayTokens: String = ""
    var todayCost: String = ""
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
        case detail = 2
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
        static let usageFontSize: CGFloat = 10
        static let usageColumnGap: CGFloat = 1
        static let usageContentInsetX: CGFloat = 6
        static let usageRowSpacing: CGFloat = 2

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

    /// 卡片外的标题项（浅色小字，置于卡片上方）
    private static func headerItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = Style.title(text)
        item.isEnabled = false
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

    /// 用量行：时间 | 模型名 | Token | 金额（Token/金额优先完整显示）
    private static func usageRow(time: String, name: String, tokens: String, cost: String) -> CardRow {
        let container = NSView()
        let gap = Style.usageColumnGap

        let timeField = NSTextField(labelWithString: time)
        timeField.font = .monospacedDigitSystemFont(ofSize: Style.usageFontSize, weight: .regular)
        timeField.textColor = MenuText.caption
        timeField.lineBreakMode = .byClipping
        timeField.sizeToFit()

        let nameField = NSTextField(labelWithString: name)
        nameField.font = .systemFont(ofSize: Style.usageFontSize, weight: .regular)
        nameField.textColor = MenuText.cardDataRow
        nameField.lineBreakMode = .byTruncatingTail
        nameField.sizeToFit()

        let tokenField = NSTextField(labelWithString: tokens)
        tokenField.font = .monospacedDigitSystemFont(ofSize: Style.usageFontSize, weight: .regular)
        tokenField.textColor = MenuText.cardDataRow
        tokenField.lineBreakMode = .byClipping
        tokenField.sizeToFit()

        let costField = NSTextField(labelWithString: cost)
        costField.font = .monospacedDigitSystemFont(ofSize: Style.usageFontSize, weight: .medium)
        costField.textColor = MenuText.cardAccent
        costField.lineBreakMode = .byClipping
        costField.sizeToFit()

        container.addSubview(timeField)
        container.addSubview(nameField)
        container.addSubview(tokenField)
        container.addSubview(costField)

        let rowHeight = max(timeField.fittingSize.height, nameField.fittingSize.height, 16)
        return CardRow(view: container, height: rowHeight) { frame in
            let costW = ceil(costField.fittingSize.width)
            let tokenW = ceil(tokenField.fittingSize.width)
            let timeW = ceil(timeField.fittingSize.width)

            let costX = frame.width - costW
            let tokenX = costX - gap - tokenW
            let nameX = timeW + gap
            let nameW = max(0, tokenX - gap - nameX)

            timeField.frame = NSRect(
                x: 0,
                y: (frame.height - timeField.fittingSize.height) / 2,
                width: timeW,
                height: timeField.fittingSize.height
            )
            nameField.frame = NSRect(
                x: nameX,
                y: (frame.height - nameField.fittingSize.height) / 2,
                width: nameW,
                height: nameField.fittingSize.height
            )
            tokenField.frame = NSRect(
                x: tokenX,
                y: (frame.height - tokenField.fittingSize.height) / 2,
                width: tokenW,
                height: tokenField.fittingSize.height
            )
            costField.frame = NSRect(
                x: costX,
                y: (frame.height - costField.fittingSize.height) / 2,
                width: costW,
                height: costField.fittingSize.height
            )
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
        populate(
            menu,
            data: data,
            isLoggedIn: isLoggedIn,
            onRefresh: onRefresh,
            onOpenSettings: onOpenSettings,
            onOpenDetail: onOpenDetail,
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
        onOpenDetail: @escaping () -> Void,
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
            onOpenDetail: onOpenDetail,
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
        onOpenDetail: @escaping () -> Void,
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
        host.set(.detail, handler: onOpenDetail)
        host.set(.browserLogin, handler: onOpenBrowserLogin)
        host.set(.checkUpdates, handler: onCheckForUpdates)
        host.set(.logout, handler: onLogout)
        host.set(.quit, handler: { NSApp.terminate(nil) })
        objc_setAssociatedObject(menu, &hostKey, host, .OBJC_ASSOCIATION_RETAIN)

        if isLoggedIn {
            // 卡片1：账单总览（标题在卡片外，右侧刷新图标按钮）
            menu.addItem(headerWithIconButton("账单总览", host: host, buttons: [
                HeaderIconButton(action: .refresh, symbolName: "arrow.clockwise", accessibilityDesc: "刷新", keepsMenuOpen: true),
            ]))
            var rows: [CardRow] = []
            if data.billingLines.isEmpty {
                rows.append(buttonRow(title: "暂无数据，点击刷新", symbolName: "arrow.clockwise",
                                      action: .refresh, host: host, hintStyle: true))
            } else {
                for line in data.billingLines { rows.append(dataRow(line)) }
            }
            menu.addItem(cardItem(rows: rows))

            // 卡片：今日用量（置于用量明细上方）
            if !data.todayTokens.isEmpty {
                menu.addItem(spacerItem(height: 6))
                menu.addItem(headerWithIconButton("今日用量", host: host, buttons: []))
                menu.addItem(cardItem(rows: [
                    dataRow("Token: \(data.todayTokens)"),
                    dataRow("金额: \(data.todayCost)"),
                ]))
            }

            // 卡片2：用量明细（标题+详情图标在卡片外，卡片内只放用量行）
            if !data.usageItems.isEmpty {
                menu.addItem(spacerItem(height: 6))
                menu.addItem(headerWithIconButton("用量明细", host: host, buttons: [
                    HeaderIconButton(action: .detail, symbolName: "arrow.up.forward.square", accessibilityDesc: "查看详情"),
                ]))
                var usageRows: [CardRow] = []
                for item in data.usageItems {
                    usageRows.append(usageRow(time: item.time, name: item.name, tokens: item.tokens, cost: item.cost))
                }
                menu.addItem(cardItem(
                    rows: usageRows,
                    contentInsetX: Style.usageContentInsetX,
                    rowSpacing: Style.usageRowSpacing
                ))
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
                cap.attributedTitle = Style.hint("上次更新: \(data.lastUpdated)")
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

    static func formatCacheHitRate(_ percent: Double?) -> String {
        guard let percent else { return "-" }
        return String(format: "%.2f%%", percent)
    }

    static func formatRequestTime(_ timestamp: Int64?) -> String {
        guard let timestamp, timestamp > 0 else { return "--/-- --:--:--" }
        let seconds: TimeInterval = timestamp > 1_000_000_000_000
            ? TimeInterval(timestamp) / 1000
            : TimeInterval(timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    static func actionHost(for menu: NSMenu?) -> MenuActionHost? {
        guard let menu else { return nil }
        return objc_getAssociatedObject(menu, &hostKey) as? MenuActionHost
    }
}

private var hostKey: UInt8 = 0