import AppKit
import Foundation

enum DefaultBrowserDetector {
    enum BrowserKind: String {
        case chrome
        case edge
        case arc
        case brave
        case tabbit
        case safari
        case unknown
    }

    static func bundleIdentifier() -> String? {
        guard let httpsURL = URL(string: "https://") else { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: httpsURL) else { return nil }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    static func displayName() -> String? {
        guard let bundleID = bundleIdentifier() else { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: appURL.path)
    }

    static func browserKind() -> BrowserKind {
        let bundleID = bundleIdentifier()?.lowercased() ?? ""
        let appName = displayName()?.lowercased() ?? ""

        if matches(bundleID, appName, keywords: ["tabbit"]) { return .tabbit }
        if bundleID == "com.apple.safari" || matches(bundleID, appName, keywords: ["safari"]) { return .safari }
        if matches(bundleID, appName, keywords: ["thebrowser", ".arc", "arc"]) { return .arc }
        if matches(bundleID, appName, keywords: ["edg", "edge"]) { return .edge }
        if matches(bundleID, appName, keywords: ["brave"]) { return .brave }
        if matches(bundleID, appName, keywords: ["chrome", "chromium"]) { return .chrome }
        return .unknown
    }

    private static func matches(_ bundleID: String, _ appName: String, keywords: [String]) -> Bool {
        keywords.contains { bundleID.contains($0) || appName.contains($0) }
    }
}

extension BrowserProfile {
    var browserKind: DefaultBrowserDetector.BrowserKind {
        switch name {
        case "Chrome": return .chrome
        case "Edge": return .edge
        case "Arc": return .arc
        case "Brave": return .brave
        case "Tabbit": return .tabbit
        default: return .unknown
        }
    }
}
