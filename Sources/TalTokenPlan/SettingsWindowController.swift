import AppKit

/// 顶部 tab：单个指示条点击后左右滑动
final class SegmentedTabView: NSView {
    private let titles: [String]
    private var buttons: [NSButton] = []
    private let indicator = NSView()
    private(set) var selectedIndex = 0
    var onChange: ((Int) -> Void)?

    private let segmentInset: CGFloat = 3

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.05).cgColor

        indicator.wantsLayer = true
        indicator.layer?.cornerCurve = .continuous
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        addSubview(indicator)

        for (i, title) in titles.enumerated() {
            let btn = NSButton()
            btn.isBordered = false
            btn.bezelStyle = .inline
            btn.attributedTitle = tabTitle(title, selected: i == 0)
            btn.alignment = .center
            btn.tag = i
            btn.target = self
            btn.action = #selector(tabClicked(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            addSubview(btn)
            buttons.append(btn)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func tabTitle(_ title: String, selected: Bool) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .medium),
                .foregroundColor: selected ? NSColor.white : NSColor.labelColor,
            ]
        )
    }

    @objc private func tabClicked(_ sender: NSButton) {
        select(sender.tag, animated: true)
    }

    func select(_ index: Int, animated: Bool) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        for (i, btn) in buttons.enumerated() {
            btn.attributedTitle = tabTitle(titles[i], selected: i == index)
        }
        moveIndicator(to: index, animated: animated)
        onChange?(index)
    }

    private func indicatorFrame(for index: Int) -> NSRect {
        let count = CGFloat(buttons.count)
        guard count > 0, bounds.width > 0 else { return .zero }
        let segW = bounds.width / count
        return NSRect(
            x: segW * CGFloat(index) + segmentInset,
            y: segmentInset,
            width: segW - segmentInset * 2,
            height: bounds.height - segmentInset * 2
        )
    }

    private func moveIndicator(to index: Int, animated: Bool) {
        let frame = indicatorFrame(for: index)
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                indicator.animator().frame = frame
            }, completionHandler: { [weak self] in
                self?.updateCornerRadii()
            })
        } else {
            indicator.frame = frame
            updateCornerRadii()
        }
    }

    private func updateCornerRadii() {
        guard bounds.height > 0 else { return }
        layer?.cornerRadius = bounds.height / 2
        let indicatorHeight = indicator.frame.height
        if indicatorHeight > 0 {
            indicator.layer?.cornerRadius = indicatorHeight / 2
        }
    }

    override func layout() {
        super.layout()
        let count = CGFloat(buttons.count)
        guard count > 0, bounds.width > 0 else { return }
        let btnW = bounds.width / count
        for (i, btn) in buttons.enumerated() {
            btn.frame = NSRect(x: btnW * CGFloat(i), y: 0, width: btnW, height: bounds.height)
        }
        if indicator.frame == .zero {
            indicator.frame = indicatorFrame(for: selectedIndex)
        }
        updateCornerRadii()
    }
}

/// ScrollView 文档视图：翻转坐标系，短内容默认从顶部显示
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}


final class SettingsWindowController: NSWindowController {
    private var segmentedControl: SegmentedTabView!
    private var contentContainer: NSScrollView!
    private var documentView: NSView!
    private var activeDocumentBottomConstraint: NSLayoutConstraint?
    private var generalView: NSView!
    private var aboutView: NSView!

    private var showRemainingSwitch: NSSwitch!
    private var showPercentageSwitch: NSSwitch!
    private var showProgressBarSwitch: NSSwitch!
    private var refreshIntervalSlider: NSSlider!
    private var refreshIntervalLabel: NSTextField!

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "设置"
        win.center()
        self.init(window: win)
        setupUI()
    }

    private func setupUI() {
        let container = window!.contentView!

        // 顶部 tab：指示条左右移动样式
        segmentedControl = SegmentedTabView(titles: ["通用", "关于"])
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.onChange = { [weak self] idx in self?.showTab(idx) }
        segmentedControl.heightAnchor.constraint(equalToConstant: 32).isActive = true

        contentContainer = NSScrollView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.hasVerticalScroller = true
        contentContainer.autohidesScrollers = true
        contentContainer.drawsBackground = false
        contentContainer.borderType = .noBorder

        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.documentView = documentView
        self.documentView = documentView

        generalView = buildGeneralView()
        aboutView = buildAboutView()

        container.addSubview(segmentedControl)
        container.addSubview(contentContainer)
        documentView.addSubview(generalView)
        documentView.addSubview(aboutView)

        let clipView = contentContainer.contentView
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            segmentedControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            contentContainer.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            contentContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            contentContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            contentContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),

            documentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: clipView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),

            generalView.topAnchor.constraint(equalTo: documentView.topAnchor),
            generalView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            generalView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),

            aboutView.topAnchor.constraint(equalTo: documentView.topAnchor),
            aboutView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            aboutView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
        ])

        showTab(0)
    }

    // MARK: - Card

    /// 纯色卡片容器（无毛玻璃）
    private func makeCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = cardFillColor().cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = cardBorderColor().cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func cardFillColor() -> NSColor {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.07)
            : NSColor(white: 0.0, alpha: 0.04)
    }

    private func cardBorderColor() -> NSColor {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.12)
            : NSColor(white: 0.0, alpha: 0.08)
    }

    private func cardSection(title: String, content: (NSStackView) -> Void) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let card = makeCard()
        wrapper.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            card.topAnchor.constraint(equalTo: wrapper.topAnchor),
            card.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(titleLabel)
        card.addSubview(contentStack)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            contentStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        content(contentStack)
        return wrapper
    }

    // MARK: - General

    private func buildGeneralView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        showRemainingSwitch = makeSwitch(title: "", value: AppSettings.showRemainingCost, action: #selector(toggleShowRemaining))
        showPercentageSwitch = makeSwitch(title: "", value: AppSettings.showPercentage, action: #selector(toggleShowPercentage))
        showProgressBarSwitch = makeSwitch(title: "", value: AppSettings.showProgressBar, action: #selector(toggleShowProgressBar))

        let remainingRow = switchRow(title: "显示剩余金额", subtitle: "关闭则显示花费金额", sw: showRemainingSwitch)
        let percentageRow = switchRow(title: "显示百分比", subtitle: nil, sw: showPercentageSwitch)
        let progressRow = switchRow(title: "显示进度条", subtitle: nil, sw: showProgressBarSwitch)

        let displayCard = cardSection(title: "状态栏显示") { stack in
            [remainingRow, percentageRow, progressRow].forEach {
                stack.addArrangedSubview($0)
                stack.addArrangedSubview(self.separator())
            }
        }

        let refreshCard = buildRefreshIntervalCard()

        let installHint = NSTextField(wrappingLabelWithString: "登录：在默认浏览器完成 cloud.tal.com 登录后，使用「从浏览器读取凭证」。首次读取时请在钥匙串弹窗中点「始终允许」。")
        installHint.font = .systemFont(ofSize: 11)
        installHint.textColor = .secondaryLabelColor
        installHint.translatesAutoresizingMaskIntoConstraints = false

        let hintCard = cardSection(title: "登录说明") { stack in
            stack.addArrangedSubview(installHint)
            installHint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let checkButton = NSButton()
        checkButton.title = "检查更新"
        checkButton.bezelStyle = .rounded
        checkButton.controlSize = .regular
        checkButton.target = self
        checkButton.action = #selector(checkForUpdates)
        let updateCard = cardSection(title: "更新") { stack in
            stack.addArrangedSubview(checkButton)
        }

        let outer = NSStackView(views: [displayCard, refreshCard, updateCard, hintCard])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 14
        outer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: view.topAnchor),
            outer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            displayCard.widthAnchor.constraint(equalTo: outer.widthAnchor),
            refreshCard.widthAnchor.constraint(equalTo: outer.widthAnchor),
            hintCard.widthAnchor.constraint(equalTo: outer.widthAnchor),
            updateCard.widthAnchor.constraint(equalTo: outer.widthAnchor),
        ])
        return view
    }

    private func buildRefreshIntervalCard() -> NSView {
        refreshIntervalLabel = NSTextField(labelWithString: "")
        refreshIntervalLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        refreshIntervalLabel.translatesAutoresizingMaskIntoConstraints = false

        refreshIntervalSlider = NSSlider(value: AppSettings.refreshInterval,
                                         minValue: 30, maxValue: 900,
                                         target: self, action: #selector(refreshIntervalChanged))
        refreshIntervalSlider.isContinuous = true
        refreshIntervalSlider.translatesAutoresizingMaskIntoConstraints = false

        updateRefreshLabel(AppSettings.refreshInterval)

        return cardSection(title: "数据自动刷新时间间隔") { stack in
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(self.refreshIntervalSlider)
            row.addSubview(self.refreshIntervalLabel)
            NSLayoutConstraint.activate([
                self.refreshIntervalSlider.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                self.refreshIntervalSlider.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                self.refreshIntervalSlider.trailingAnchor.constraint(equalTo: self.refreshIntervalLabel.leadingAnchor, constant: -8),
                self.refreshIntervalLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                self.refreshIntervalLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                self.refreshIntervalLabel.widthAnchor.constraint(equalToConstant: 50),
                row.heightAnchor.constraint(equalToConstant: 24),
            ])
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @objc private func refreshIntervalChanged() {
        let v = refreshIntervalSlider.doubleValue
        // 经过整分钟刻度时触发触觉反馈，给"卡一下"的感觉
        let prevMinute = Int(AppSettings.refreshInterval) / 60
        let currMinute = Int(v) / 60
        if prevMinute != currMinute {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        AppSettings.refreshInterval = v
        updateRefreshLabel(v)
    }

    private func updateRefreshLabel(_ seconds: Double) {
        if seconds < 60 {
            refreshIntervalLabel.stringValue = "\(Int(seconds))s"
        } else {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            refreshIntervalLabel.stringValue = s == 0 ? "\(m)min" : "\(m)m\(s)s"
        }
    }

    // MARK: - About

    private func buildAboutView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: AppInfo.name)
        nameLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let versionLabel = NSTextField(labelWithString: "版本 \(AppInfo.version)")
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor

        let aboutCard = cardSection(title: "关于") { stack in
            stack.addArrangedSubview(nameLabel)
            stack.addArrangedSubview(versionLabel)
        }

        let outer = NSStackView(views: [aboutCard])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 14
        outer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            outer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: outer.bottomAnchor, constant: 8),
            aboutCard.widthAnchor.constraint(equalTo: outer.widthAnchor),
        ])
        return view
    }

    @objc private func checkForUpdates() {
        AppUpdaterManager.shared.checkForUpdates()
    }

    // MARK: - Helpers

    private func makeSwitch(title: String, value: Bool, action: Selector) -> NSSwitch {
        let s = NSSwitch()
        s.state = value ? .on : .off
        s.target = self
        s.action = action
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    /// 标签 + 右侧开关横排，可选副标题
    private func switchRow(title: String, subtitle: String?, sw: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(sw)

        var constraints: [NSLayoutConstraint] = [
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            sw.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            sw.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ]

        if let subtitle = subtitle {
            let sub = NSTextField(labelWithString: subtitle)
            sub.font = .systemFont(ofSize: 11)
            sub.textColor = .secondaryLabelColor
            sub.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(sub)
            constraints += [
                sub.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                sub.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 2),
                sw.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        return row
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func showTab(_ index: Int) {
        generalView.isHidden = index != 0
        aboutView.isHidden = index != 1

        activeDocumentBottomConstraint?.isActive = false
        let activeView: NSView = index == 0 ? generalView! : aboutView!
        activeDocumentBottomConstraint = activeView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        activeDocumentBottomConstraint?.isActive = true

        scrollContentToTop()
    }

    private func scrollContentToTop() {
        let clipView = contentContainer.contentView
        clipView.scroll(to: .zero)
        contentContainer.reflectScrolledClipView(clipView)
    }

    @objc private func toggleShowRemaining() {
        AppSettings.showRemainingCost = showRemainingSwitch.state == .on
    }

    @objc private func toggleShowPercentage() {
        AppSettings.showPercentage = showPercentageSwitch.state == .on
    }

    @objc private func toggleShowProgressBar() {
        AppSettings.showProgressBar = showProgressBarSwitch.state == .on
    }

    func showSettings() {
        showRemainingSwitch.state = AppSettings.showRemainingCost ? .on : .off
        showPercentageSwitch.state = AppSettings.showPercentage ? .on : .off
        showProgressBarSwitch.state = AppSettings.showProgressBar ? .on : .off
        refreshIntervalSlider.doubleValue = AppSettings.refreshInterval
        updateRefreshLabel(AppSettings.refreshInterval)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
