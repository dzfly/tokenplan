import Foundation

enum ChromiumLocalStorageReader {
    /// 仅在 leveldb 中查找与 cloud.tal.com 关联的 JWT，避免误读 cloud-test 等环境 token
    static func findCloudTalToken(profileDir: URL) -> String? {
        let leveldbDir = profileDir.appendingPathComponent("Local Storage/leveldb")
        guard FileManager.default.fileExists(atPath: leveldbDir.path) else { return nil }

        guard let files = try? FileManager.default.contentsOfDirectory(at: leveldbDir, includingPropertiesForKeys: nil) else {
            return nil
        }

        for file in files {
            let ext = file.pathExtension.lowercased()
            guard ext == "ldb" || ext == "log" else { continue }
            guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { continue }
            if let token = scanData(data) { return token }
        }
        return nil
    }

    private static func scanData(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return nil
        }

        let pattern = "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let jwt = nsText.substring(with: match.range)
            guard JWTHelper.isStructurallyValid(jwt), !JWTHelper.isExpired(jwt) else { continue }

            let start = max(0, match.range.location - 200)
            let contextRange = NSRange(location: start, length: match.range.location + match.range.length - start)
            let context = nsText.substring(with: contextRange)

            guard context.contains("cloud.tal.com") else { continue }
            guard !context.contains("cloud-test.tal.com") else { continue }
            return jwt
        }
        return nil
    }
}
