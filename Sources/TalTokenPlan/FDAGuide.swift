import AppKit

enum FDAGuide {
    static func showPermissionGuide(appName: String = AppInfo.name) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要「完全磁盘访问」权限"
        alert.informativeText = """
        读取浏览器 Cookie 需要授权：

        1. 打开「系统设置 → 隐私与安全性 → 完全磁盘访问」
        2. 点击 + ，添加「\(appName)」
        3. 若已添加，请关闭后重新打开开关
        4. 完全退出并重新启动 \(appName)
        5. 确保已在 Chrome / Edge / Arc / Tabbit / Safari 中登录 cloud.tal.com

        授权后再次点击「从浏览器读取凭证」。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            openPrivacySettings()
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
