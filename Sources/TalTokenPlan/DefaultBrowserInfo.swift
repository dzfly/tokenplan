import AppKit
import Foundation

enum DefaultBrowserInfo {
    static var displayName: String? {
        guard let httpsURL = URL(string: "https://") else { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: httpsURL) else { return nil }
        return FileManager.default.displayName(atPath: appURL.path)
    }
}
