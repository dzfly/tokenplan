import Foundation

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("appSettingsDidChange")
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let showRemainingCost = "showRemainingCost"
        static let showPercentage = "showPercentage"
        static let showProgressBar = "showProgressBar"
    }

    static var showRemainingCost: Bool {
        get { defaults.bool(forKey: Key.showRemainingCost) }
        set { defaults.set(newValue, forKey: Key.showRemainingCost); notifyChange() }
    }

    static var showPercentage: Bool {
        get {
            if defaults.object(forKey: Key.showPercentage) == nil { return true }
            return defaults.bool(forKey: Key.showPercentage)
        }
        set { defaults.set(newValue, forKey: Key.showPercentage); notifyChange() }
    }

    static var showProgressBar: Bool {
        get {
            if defaults.object(forKey: Key.showProgressBar) == nil { return true }
            return defaults.bool(forKey: Key.showProgressBar)
        }
        set { defaults.set(newValue, forKey: Key.showProgressBar); notifyChange() }
    }

    private static func notifyChange() {
        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
    }
}

enum AppInfo {
    static var name: String {
        if let n = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String { return n }
        if let n = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String { return n }
        return "Token Plan"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
