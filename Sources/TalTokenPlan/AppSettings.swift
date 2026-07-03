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
        static let refreshInterval = "refreshInterval"
        static let hasShownKeychainNotice = "hasShownKeychainNotice"
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

    static var hasShownKeychainNotice: Bool {
        get { defaults.bool(forKey: Key.hasShownKeychainNotice) }
        set { defaults.set(newValue, forKey: Key.hasShownKeychainNotice) }
    }

    // 30s–900s，默认 60s
    static var refreshInterval: TimeInterval {
        get {
            let v = defaults.double(forKey: Key.refreshInterval)
            return v > 0 ? v : 60
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval); notifyChange() }
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
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { return v }
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let v = dict["CFBundleShortVersionString"] as? String { return v }
        return "1.0"
    }
}
