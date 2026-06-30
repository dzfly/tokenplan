import Foundation

final class CookieDebugContext {
    static var current = CookieDebugContext()

    private(set) var lines: [String] = []

    func reset() {
        lines = []
    }

    func branch(_ line: String) {
        lines.append(line)
    }

    func report() -> String {
        lines.joined(separator: "\n")
    }
}
