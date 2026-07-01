import Foundation
import AppKit
import Sparkle

/// Sparkle 自动更新（App 内称 AppUpdater）
final class AppUpdaterManager: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdaterManager()

    private var controller: SPUStandardUpdaterController?
    private var manualChecking = false

    private override init() { super.init() }

    func start() {
        guard controller == nil else { return }
        let updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updater.updater.automaticallyChecksForUpdates = true
        updater.updater.updateCheckInterval = 86_400
        controller = updater
    }

    /// 用户手动检查：激活 app 置顶 + 触发 Sparkle 检查；无新版本/出错通过 delegate 弹提示
    func checkForUpdates() {
        manualChecking = true
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard manualChecking else { return }
        manualChecking = false
        DispatchQueue.main.async {
            // Sparkle 2 自带「无新版本/最新版」和更新窗口,这里只在出错时提示
            if let error = error as NSError? {
                if error.code == 1001 || error.code == 1002 {
                    // 无新版本(Sparkle 已提示) / 用户取消,不额外弹窗
                } else {
                    self.alertError(error)
                }
            }
        }
    }

    private func alertError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "检查更新失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
