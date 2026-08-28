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
        // debug 包不检查更新（SwiftPM debug 构建定义 DEBUG，release 不定义）
        #if DEBUG
        return
        #endif
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
        #if DEBUG
        return
        #endif
        manualChecking = true
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard manualChecking else { return }
        manualChecking = false
        // 手动检查时 Sparkle 自己负责所有 UI（有新版本/无新版本/报错），不额外弹窗
    }

}
