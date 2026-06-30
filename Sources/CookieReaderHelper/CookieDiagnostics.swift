import Foundation

enum CookieDiagnostics {
    static func printReport() {
        var lines: [String] = []
        lines.append("── Cookie 诊断 ──")

        let kind = DefaultBrowserDetector.browserKind()
        let name = DefaultBrowserDetector.displayName() ?? kind.rawValue
        lines.append("默认浏览器: \(name) (\(kind.rawValue))")
        lines.append("仅读取默认浏览器；★ = cloud.tal.com/Authorization（目标 Cookie）")

        if !CookieDebugContext.current.lines.isEmpty {
            lines.append("")
            lines.append("读取分支:")
            lines.append(contentsOf: CookieDebugContext.current.lines)
        } else {
            lines.append("")
            appendDefaultBrowserSnapshot(to: &lines, kind: kind, browserName: name)
        }

        lines.append("")
        lines.append("提示: cloud-test.tal.com/Authorization 会被忽略；需在 cloud.tal.com 重新登录")
        fputs(lines.joined(separator: "\n") + "\n", stderr)
    }

    private static func appendDefaultBrowserSnapshot(to lines: inout [String], kind: DefaultBrowserDetector.BrowserKind, browserName: String) {
        if kind == .safari {
            for path in SafariBinaryCookiesReader.diagnosticPaths() {
                let readable = FileManager.default.isReadableFile(atPath: path.path)
                lines.append("- Safari [默认]: \(readable ? "可读" : "不可读") Cookies")
                if readable {
                    lines.append(contentsOf: SafariBinaryCookiesReader.inspectCloudAuthorization(at: path))
                }
            }
            return
        }

        let profiles = CookieReader.defaultBrowserProfiles()
        if profiles.isEmpty {
            lines.append("- 未找到 \(browserName) 的 Cookie 目录")
            return
        }

        for profile in profiles {
            lines.append(contentsOf: CookieReader.listTalCookieSummary(for: profile, isDefault: true))
        }
    }
}
