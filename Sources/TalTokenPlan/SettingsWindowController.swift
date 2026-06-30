import AppKit

final class SettingsWindowController: NSWindowController {
    private var segmentedControl: NSSegmentedControl!
    private var contentContainer: NSView!
    private var generalView: NSView!
    private var aboutView: NSView!

    private var showRemainingSwitch: NSButton!
    private var showPercentageSwitch: NSButton!
    private var showProgressBarSwitch: NSButton!

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
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

        segmentedControl = NSSegmentedControl(labels: ["通用", "关于"], trackingMode: .selectOne, target: self, action: #selector(tabChanged))
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        generalView = buildGeneralView()
        aboutView = buildAboutView()

        container.addSubview(segmentedControl)
        container.addSubview(contentContainer)
        contentContainer.addSubview(generalView)
        contentContainer.addSubview(aboutView)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            contentContainer.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            contentContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            generalView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            generalView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            generalView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),
            generalView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            aboutView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            aboutView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            aboutView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),
            aboutView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        showTab(0)
    }

    private func buildGeneralView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        showRemainingSwitch = makeSwitch(title: "显示剩余费用", value: AppSettings.showRemainingCost, action: #selector(toggleShowRemaining))
        showPercentageSwitch = makeSwitch(title: "显示百分比", value: AppSettings.showPercentage, action: #selector(toggleShowPercentage))
        showProgressBarSwitch = makeSwitch(title: "进度条", value: AppSettings.showProgressBar, action: #selector(toggleShowProgressBar))

        let installHint = NSTextField(wrappingLabelWithString: "登录：在默认浏览器完成 cloud.tal.com 登录后，使用「从浏览器读取凭证」。首次读取时请在钥匙串弹窗中点「始终允许」。")
        installHint.font = NSFont.systemFont(ofSize: 11)
        installHint.textColor = .secondaryLabelColor
        installHint.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [showRemainingSwitch, showPercentageSwitch, showProgressBarSwitch, installHint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            installHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return view
    }

    private func buildAboutView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: AppInfo.name)
        nameLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        let versionLabel = NSTextField(labelWithString: "版本 \(AppInfo.version)")
        versionLabel.font = NSFont.systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [nameLabel, versionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ])
        return view
    }

    private func makeSwitch(title: String, value: Bool, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.setButtonType(.switch)
        btn.title = title
        btn.target = self
        btn.action = action
        btn.state = value ? .on : .off
        return btn
    }

    @objc private func tabChanged() {
        showTab(segmentedControl.selectedSegment)
    }

    private func showTab(_ index: Int) {
        generalView.isHidden = index != 0
        aboutView.isHidden = index != 1
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
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
