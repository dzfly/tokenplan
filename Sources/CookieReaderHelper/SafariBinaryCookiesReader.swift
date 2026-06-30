import Foundation

enum SafariBinaryCookiesReader {
    private static let cookiePaths: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"),
            home.appendingPathComponent("Library/Cookies/Cookies.binarycookies"),
        ]
    }()

    static func diagnosticPaths() -> [URL] { cookiePaths }

    static func findCloudAuthorization(debug: CookieDebugContext) -> Result<String, HelperError> {
        for path in cookiePaths {
            let readable = FileManager.default.isReadableFile(atPath: path.path)
            debug.branch("   路径: \(path.lastPathComponent) → \(readable ? "可读" : "不可读")")
            guard readable else { continue }

            switch readCloudAuthorization(at: path, debug: debug) {
            case .success(let token):
                return .success(token)
            case .failure(.notFound):
                continue
            case .failure(let error):
                return .failure(error)
            }
        }
        debug.branch("   未找到 cloud.tal.com/Authorization")
        return .failure(.notFound)
    }

    static func inspectCloudAuthorization(at url: URL) -> [String] {
        var lines: [String] = []
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            lines.append("  Cookie 文件不可读")
            return lines
        }

        guard let data = try? Data(contentsOf: url) else {
            lines.append("  Cookie 文件读取失败")
            return lines
        }

        guard data.count >= 8, data.prefix(4) == Data("cook".utf8) else {
            lines.append("  非 binarycookies 格式")
            return lines
        }

        let pageCount = readUInt32BE(data, offset: 4)
        var offset = 8
        var pageSizes: [UInt32] = []
        for _ in 0..<pageCount {
            guard offset + 4 <= data.count else { break }
            pageSizes.append(readUInt32BE(data, offset: offset))
            offset += 4
        }

        var authCount = 0
        for size in pageSizes {
            guard offset + Int(size) <= data.count else { break }
            let page = data.subdata(in: offset..<(offset + Int(size)))
            offset += Int(size)
            authCount += inspectPage(page, lines: &lines)
        }

        if authCount == 0 {
            lines.append("  未找到 cloud.tal.com/Authorization Cookie")
            lines.append("  请在 Safari 打开 cloud.tal.com 并完成登录")
        }
        return lines
    }

    private static func readCloudAuthorization(at url: URL, debug: CookieDebugContext) -> Result<String, HelperError> {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            debug.branch("   Cookie 文件不可读 → 需「完全磁盘访问」")
            return .failure(.permissionDenied(path: url.path))
        }

        guard let data = try? Data(contentsOf: url) else {
            debug.branch("   Cookie 文件读取失败")
            return .failure(.permissionDenied(path: url.path))
        }

        guard data.count >= 8, data.prefix(4) == Data("cook".utf8) else {
            debug.branch("   非 binarycookies 格式")
            return .failure(.databaseError)
        }

        let pageCount = readUInt32BE(data, offset: 4)
        var offset = 8
        var pageSizes: [UInt32] = []
        for _ in 0..<pageCount {
            guard offset + 4 <= data.count else { return .failure(.databaseError) }
            pageSizes.append(readUInt32BE(data, offset: offset))
            offset += 4
        }

        for size in pageSizes {
            guard offset + Int(size) <= data.count else { return .failure(.databaseError) }
            let page = data.subdata(in: offset..<(offset + Int(size)))
            offset += Int(size)
            if let token = parseCloudAuthorizationPage(page, debug: debug) {
                return .success(token)
            }
        }

        return .failure(.notFound)
    }

    @discardableResult
    private static func inspectPage(_ page: Data, lines: inout [String]) -> Int {
        guard page.count >= 8, readUInt32BE(page, offset: 0) == 0x0000_0100 else { return 0 }
        let cookieCount = readUInt32LE(page, offset: 4)
        var cursor = 8
        var authCount = 0

        for _ in 0..<cookieCount {
            guard cursor + 4 <= page.count else { break }
            let recordSize = Int(readUInt32LE(page, offset: cursor))
            guard recordSize > 0, cursor + recordSize <= page.count else { break }
            let record = page.subdata(in: cursor..<(cursor + recordSize))
            cursor += recordSize

            guard record.count >= 32 else { continue }
            let urlOffset = Int(readUInt32LE(record, offset: 12))
            let nameOffset = Int(readUInt32LE(record, offset: 16))
            let valueOffset = Int(readUInt32LE(record, offset: 24))

            let domain = readNullTerminatedString(record, offset: urlOffset)
            let name = readNullTerminatedString(record, offset: nameOffset)
            let value = readNullTerminatedString(record, offset: valueOffset)

            guard TokenNormalizer.isCloudTalHost(domain), name.lowercased() == "authorization" else { continue }
            authCount += 1
            let jwt = TokenNormalizer.parseCloudAuthorization(value) != nil
            let exp = TokenNormalizer.parseCloudAuthorization(value).map { JWTHelper.expirationDescription($0) } ?? "无效"
            lines.append("  Cookie[\(authCount)]: \(domain)/\(name), JWT=\(jwt ? "有效" : "无效"), \(exp)")
        }
        return authCount
    }

    private static func parseCloudAuthorizationPage(_ page: Data, debug: CookieDebugContext?) -> String? {
        guard page.count >= 8, readUInt32BE(page, offset: 0) == 0x0000_0100 else { return nil }
        let cookieCount = readUInt32LE(page, offset: 4)
        var cursor = 8

        for _ in 0..<cookieCount {
            guard cursor + 4 <= page.count else { return nil }
            let recordSize = Int(readUInt32LE(page, offset: cursor))
            guard recordSize > 0, cursor + recordSize <= page.count else { return nil }
            let record = page.subdata(in: cursor..<(cursor + recordSize))
            cursor += recordSize

            guard record.count >= 32 else { continue }
            let urlOffset = Int(readUInt32LE(record, offset: 12))
            let nameOffset = Int(readUInt32LE(record, offset: 16))
            let valueOffset = Int(readUInt32LE(record, offset: 24))

            let domain = readNullTerminatedString(record, offset: urlOffset)
            let name = readNullTerminatedString(record, offset: nameOffset)
            let value = readNullTerminatedString(record, offset: valueOffset)

            if TokenNormalizer.isCloudTalHost(domain), name.lowercased() == "authorization" {
                let jwt = TokenNormalizer.parseCloudAuthorization(value) != nil
                debug?.branch("   Cookie: \(domain)/\(name), 长度=\(value.count), JWT=\(jwt ? "有效" : "无效")")
                if let token = TokenExtractor.parse(value, cookieName: name, host: domain) {
                    return token
                }
            }
        }
        return nil
    }

    private static func readNullTerminatedString(_ data: Data, offset: Int) -> String {
        guard offset >= 0, offset < data.count else { return "" }
        var end = offset
        while end < data.count, data[end] != 0 { end += 1 }
        return String(data: data.subdata(in: offset..<end), encoding: .utf8) ?? ""
    }

    private static func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }
}
