import Foundation

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("appSettingsDidChange")
}

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var segmentIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    init(segmentIndex: Int) {
        self = Self.allCases.indices.contains(segmentIndex) ? Self.allCases[segmentIndex] : .system
    }
}

enum StatusBarStyle: String, CaseIterable {
    /// 简约：纯额度环
    case compact
    /// 经典：环 + 双行数字（默认）
    case classic
    /// 丰富：标签 + 进度条 + 金额
    case rich

    var title: String {
        switch self {
        case .compact: return "简约"
        case .classic: return "经典"
        case .rich: return "丰富"
        }
    }

    var segmentIndex: Int { Self.allCases.firstIndex(of: self) ?? 1 }

    init(segmentIndex: Int) {
        self = Self.allCases.indices.contains(segmentIndex) ? Self.allCases[segmentIndex] : .classic
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let hasShownKeychainNotice = "hasShownKeychainNotice"
        static let appearanceMode = "appearanceMode"
        static let paletteID = "paletteID"
        static let statusBarStyle = "statusBarStyle"
    }

    static var hasShownKeychainNotice: Bool {
        get { defaults.bool(forKey: Key.hasShownKeychainNotice) }
        set { defaults.set(newValue, forKey: Key.hasShownKeychainNotice) }
    }

    static var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.string(forKey: Key.appearanceMode) ?? "") ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: Key.appearanceMode); notifyChange() }
    }

    static var paletteID: String {
        get { defaults.string(forKey: Key.paletteID) ?? DashboardTheme.defaultPaletteID }
        set { defaults.set(newValue, forKey: Key.paletteID); notifyChange() }
    }

    static var statusBarStyle: StatusBarStyle {
        get { StatusBarStyle(rawValue: defaults.string(forKey: Key.statusBarStyle) ?? "") ?? .classic }
        set { defaults.set(newValue.rawValue, forKey: Key.statusBarStyle); notifyChange() }
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
