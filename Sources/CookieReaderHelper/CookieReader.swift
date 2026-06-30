import Foundation
import SQLite3

struct BrowserProfile {
    let name: String
    let cookiesPath: URL
    let keychainService: String
    let keychainAccount: String

    var profileDir: URL {
        cookiesPath.deletingLastPathComponent()
    }
}

enum CookieReader {
    static func findToken() -> Result<String, HelperError> {
        CookieDebugContext.current.reset()
        let ctx = CookieDebugContext.current
        let kind = DefaultBrowserDetector.browserKind()
        let browserName = DefaultBrowserDetector.displayName() ?? kind.rawValue

        ctx.branch("① 检测默认浏览器 → \(browserName) (\(kind.rawValue))")
        ctx.branch("② 策略: 仅读取该浏览器 Cookie")

        if kind == .safari {
            ctx.branch("③ 读取 Safari binarycookies")
            switch SafariBinaryCookiesReader.findCloudAuthorization(debug: ctx) {
            case .success(let token):
                ctx.branch("④ ✅ 找到 JWT, \(JWTHelper.expirationDescription(token))")
                return validateAndReturn(token, ctx: ctx)
            case .failure(let error):
                return .failure(error)
            }
        }

        guard kind != .unknown else {
            ctx.branch("③ ❌ 无法识别默认浏览器")
            return .failure(.notFound)
        }

        let profiles = defaultBrowserProfiles()
        guard !profiles.isEmpty else {
            ctx.branch("③ ❌ 未找到 \(browserName) 的 Cookie 目录")
            return .failure(.notFound)
        }

        var lastError: HelperError = .notFound
        for profile in profiles {
            ctx.branch("③ 读取 \(profile.name) (\(profile.cookiesPath.deletingLastPathComponent().lastPathComponent))")
            switch readCloudAuthorization(from: profile, debug: ctx) {
            case .success(let token):
                ctx.branch("④ ✅ 找到 JWT, \(JWTHelper.expirationDescription(token))")
                return validateAndReturn(token, ctx: ctx)
            case .failure(let error):
                lastError = error
            }
        }

        if let profile = profiles.first,
           let token = ChromiumLocalStorageReader.findCloudTalToken(profileDir: profile.profileDir) {
            ctx.branch("④ ✅ 从 localStorage(cloud.tal.com) 找到 JWT")
            return validateAndReturn(token, ctx: ctx)
        }
        ctx.branch("④ ❌ localStorage 无 cloud.tal.com JWT")

        return .failure(lastError)
    }

    private static func validateAndReturn(_ token: String, ctx: CookieDebugContext) -> Result<String, HelperError> {
        if JWTHelper.isExpired(token) {
            ctx.branch("   JWT 过期: \(JWTHelper.expirationDescription(token))")
            return .failure(.tokenExpired)
        }
        return .success(token)
    }

    static func defaultBrowserProfiles() -> [BrowserProfile] {
        let kind = DefaultBrowserDetector.browserKind()
        guard kind != .safari, kind != .unknown else { return [] }
        return chromiumProfiles().filter { $0.browserKind == kind }
    }

    static func inspectCloudAuthorization(for profile: BrowserProfile) -> [String] {
        var lines: [String] = []
        guard FileManager.default.isReadableFile(atPath: profile.cookiesPath.path) else {
            lines.append("  Cookie 文件不可读")
            return lines
        }

        guard let password = ChromiumDecryptor.keychainPassword(service: profile.keychainService, account: profile.keychainAccount) else {
            lines.append("  Keychain 密钥不可读")
            return lines
        }

        guard let db = openTempDatabase(from: profile.cookiesPath) else {
            lines.append("  Cookie 数据库打开失败")
            return lines
        }
        defer { sqlite3_close(db) }

        lines.append(contentsOf: inspectAuthorizationRows(db: db, password: password, indent: "  "))
        return lines
    }

    private static func readCloudAuthorization(from profile: BrowserProfile, debug: CookieDebugContext) -> Result<String, HelperError> {
        guard FileManager.default.isReadableFile(atPath: profile.cookiesPath.path) else {
            debug.branch("   Cookie 文件不可读 → 需「完全磁盘访问」")
            return .failure(.permissionDenied(path: profile.cookiesPath.path))
        }
        debug.branch("   Cookie 文件可读")

        guard let password = ChromiumDecryptor.keychainPassword(service: profile.keychainService, account: profile.keychainAccount) else {
            debug.branch("   Keychain 密钥不可读 → 请在钥匙串中允许")
            return .failure(.keychainDenied(browser: profile.name))
        }
        debug.branch("   Keychain 密钥可读")

        guard let db = openTempDatabase(from: profile.cookiesPath) else {
            debug.branch("   Cookie 数据库打开失败")
            return .failure(.databaseError)
        }
        defer { sqlite3_close(db) }

        for line in inspectAuthorizationRows(db: db, password: password, indent: "   ") {
            debug.branch(line)
        }

        switch extractToken(db: db, password: password) {
        case .success(let token):
            return .success(token)
        case .failure(.tokenExpired):
            return .failure(.tokenExpired)
        case .failure(.notFound):
            return .failure(.notFound)
        }
    }

    private static func inspectAuthorizationRows(db: OpaquePointer, password: String, indent: String) -> [String] {
        guard let schema = ChromiumCookieSchema.detect(db: db) else {
            return ["\(indent)无法识别 cookies 表结构"]
        }

        let plan = ChromiumCookieQuery.cloudAuthorizationPlan(for: schema)
        switch CloudAuthorizationFetcher.fetchRows(db: db, plan: plan, password: password) {
        case .success(let rows):
            return CloudAuthorizationFetcher.inspectRows(rows, password: password, indent: indent)
        case .failure(.queryFailed(let message)):
            return [
                "\(indent)查询失败: \(message)",
                "\(indent)表字段: \(schema.columnSummary())",
            ]
        case .failure(.schemaUnsupported(let message)):
            return [
                "\(indent)表结构不支持: \(message)",
                "\(indent)表字段: \(schema.columnSummary())",
            ]
        }
    }

    private static func extractToken(db: OpaquePointer, password: String) -> Result<String, ExtractError> {
        guard let schema = ChromiumCookieSchema.detect(db: db) else {
            return .failure(.notFound)
        }

        let plan = ChromiumCookieQuery.cloudAuthorizationPlan(for: schema)
        switch CloudAuthorizationFetcher.fetchRows(db: db, plan: plan, password: password) {
        case .failure:
            return .failure(.notFound)
        case .success(let rows):
            switch CloudAuthorizationFetcher.extractToken(from: rows, password: password) {
            case .found(let token):
                return .success(token)
            case .expired:
                return .failure(.tokenExpired)
            case .notFound, .invalidValue:
                return .failure(.notFound)
            }
        }
    }

    private enum ExtractError: Error {
        case notFound
        case tokenExpired
    }

    private static func openTempDatabase(from cookiesPath: URL) -> OpaquePointer? {
        CookieDatabase.openReadonlyCopy(from: cookiesPath)
    }

    private static func chromiumProfiles() -> [BrowserProfile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support")
        var profiles: [BrowserProfile] = []

        let browsers: [(String, URL, String, String)] = [
            ("Chrome", appSupport.appendingPathComponent("Google/Chrome"), "Chrome Safe Storage", "Chrome"),
            ("Edge", appSupport.appendingPathComponent("Microsoft Edge"), "Microsoft Edge Safe Storage", "Microsoft Edge"),
            ("Arc", appSupport.appendingPathComponent("Arc/User Data"), "Arc Safe Storage", "Arc"),
            ("Brave", appSupport.appendingPathComponent("BraveSoftware/Brave-Browser"), "Brave Safe Storage", "Brave"),
            ("Tabbit", appSupport.appendingPathComponent("Tabbit Browser"), "Tabbit Browser Safe Storage", "Tabbit Browser"),
        ]

        for (name, base, service, account) in browsers {
            profiles.append(contentsOf: discoverChromiumProfiles(name: name, base: base, service: service, account: account))
        }
        return profiles
    }

    private static func discoverChromiumProfiles(name: String, base: URL, service: String, account: String) -> [BrowserProfile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return [] }

        var paths: [URL] = []
        let defaultCookies = base.appendingPathComponent("Default/Cookies")
        if fm.fileExists(atPath: defaultCookies.path) { paths.append(defaultCookies) }

        if let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in items where item.lastPathComponent.hasPrefix("Profile ") {
                let cookies = item.appendingPathComponent("Cookies")
                if fm.fileExists(atPath: cookies.path) { paths.append(cookies) }
            }
        }

        return paths.map { BrowserProfile(name: name, cookiesPath: $0, keychainService: service, keychainAccount: account) }
    }

    static func listTalCookieSummary(for profile: BrowserProfile, isDefault: Bool) -> [String] {
        var lines: [String] = []
        let label = isDefault ? "\(profile.name) [默认]" : profile.name
        guard FileManager.default.isReadableFile(atPath: profile.cookiesPath.path) else {
            lines.append("- \(label): 不可读 Cookies")
            return lines
        }
        lines.append("- \(label): 可读 Cookies")

        guard let db = openTempDatabase(from: profile.cookiesPath) else {
            lines.append("  Cookie 数据库打开失败")
            return lines
        }
        defer { sqlite3_close(db) }

        if let schema = ChromiumCookieSchema.detect(db: db) {
            lines.append("  表字段: \(schema.columnSummary())")
        }

        let sql = """
            SELECT host_key, name FROM cookies
            WHERE host_key LIKE '%tal.com%' OR host_key LIKE '%100tal.com%'
            ORDER BY host_key, name
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return lines }
        defer { sqlite3_finalize(stmt) }

        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let host = stringColumn(stmt, 0) ?? ""
            let name = stringColumn(stmt, 1) ?? ""
            let marker = TokenNormalizer.isCloudTalHost(host) && name.lowercased() == "authorization" ? " ★" : ""
            names.append("\(host)/\(name)\(marker)")
        }

        if names.isEmpty {
            lines.append("  (无 tal.com Cookie)")
        } else {
            lines.append("  Cookie: \(names.joined(separator: ", "))")
        }

        if let password = ChromiumDecryptor.keychainPassword(service: profile.keychainService, account: profile.keychainAccount) {
            lines.append(contentsOf: inspectAuthorizationRows(db: db, password: password, indent: "  "))
        }
        return lines
    }

    private static func stringColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }
}

enum HelperError: Error, CustomStringConvertible {
    case notFound
    case tokenExpired
    case permissionDenied(path: String)
    case keychainDenied(browser: String)
    case databaseError

    var description: String {
        switch self {
        case .notFound:
            return "未在默认浏览器的 cloud.tal.com 找到有效 Authorization 凭证"
        case .tokenExpired:
            return "cloud.tal.com Authorization 已过期，请在默认浏览器重新登录"
        case .permissionDenied:
            return "无法读取默认浏览器 Cookie，请授予 Token Plan「完全磁盘访问」并重启"
        case .keychainDenied(let browser):
            return "无法读取 \(browser) 钥匙串密钥"
        case .databaseError:
            return "Cookie 数据库读取失败"
        }
    }

    var exitCode: Int32 {
        switch self {
        case .notFound: return 1
        case .tokenExpired: return 5
        case .permissionDenied: return 2
        case .keychainDenied: return 3
        case .databaseError: return 4
        }
    }
}
