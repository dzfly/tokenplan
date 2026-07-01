import Foundation
import Sparkle

/// Sparkle 自动更新（App 内称 AppUpdater）
final class AppUpdaterManager {
    static let shared = AppUpdaterManager()

    private var controller: SPUStandardUpdaterController?

    private init() {}

    func start() {
        guard controller == nil else { return }
        let updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updater.updater.automaticallyChecksForUpdates = true
        updater.updater.updateCheckInterval = 86_400
        controller = updater
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
