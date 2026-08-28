import AppKit
import SwiftUI

final class MainWindowController: NSWindowController {
    private var effectView: NSVisualEffectView?

    init(viewModel: DashboardViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tal Token Plan"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        DashboardTheme.apply()
        window.appearance = AppSettings.appearanceMode.nsAppearance
        // 毛玻璃：窗口透明，NSVisualEffectView 提供模糊层
        window.isOpaque = false
        window.backgroundColor = .clear
        // 关闭仅隐藏窗口，菜单栏应用继续运行（codexU 同款行为）
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720))
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        self.effectView = effect

        let hostingView = NSHostingView(rootView: DashboardView(viewModel: viewModel))
        hostingView.frame = effect.bounds
        hostingView.autoresizingMask = [.width, .height]
        effect.addSubview(hostingView)
        window.contentView = effect
        window.minSize = NSSize(width: 880, height: 640)
        window.contentMinSize = NSSize(width: 880, height: 640)
        // 启动路径与设置变更路径共用同一份材质/外观逻辑，
        // 否则默认 material(.titlebar) 会渲染成不透明纯色
        syncAppearance(AppSettings.appearanceMode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func syncAppearance(_ mode: AppearanceMode) {
        DashboardTheme.apply()
        window?.appearance = mode.nsAppearance
        effectView?.material = DashboardTheme.isDark ? .hudWindow : .windowBackground
    }
}
