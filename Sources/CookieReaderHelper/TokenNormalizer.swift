import Foundation

enum TokenNormalizer {
    static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.lowercased().hasPrefix("authorization:") {
            text = String(text.dropFirst("authorization:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        while text.lowercased().hasPrefix("bearer ") {
            text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("'") && text.hasSuffix("'")) {
            text = String(text.dropFirst().dropLast())
        }

        if let decoded = text.removingPercentEncoding, decoded != text {
            text = decoded
        }

        return text.isEmpty ? nil : text
    }

    static func isCloudTalHost(_ host: String) -> Bool {
        host == "cloud.tal.com" || host == ".cloud.tal.com"
    }

    static func isValidJWT(_ value: String) -> Bool {
        JWTHelper.isStructurallyValid(value)
    }

    /// cloud.tal.com 的 Authorization 必须是合法 JWT
    static func parseCloudAuthorization(_ raw: String) -> String? {
        guard let text = normalize(raw) else { return nil }

        if isValidJWT(text) { return text }

        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["token", "accessToken", "access_token", "authorization", "value"] {
                if let nested = json[key] as? String, let token = parseCloudAuthorization(nested) {
                    return token
                }
            }
        }

        return JWTHelper.extractFromText(text)
    }
}

enum TokenExtractor {
    static func parse(_ raw: String, cookieName: String, host: String) -> String? {
        let name = cookieName.lowercased()

        if TokenNormalizer.isCloudTalHost(host), name == "authorization" {
            return TokenNormalizer.parseCloudAuthorization(raw)
        }

        guard let text = TokenNormalizer.normalize(raw) else { return nil }
        if TokenNormalizer.isValidJWT(text) { return text }

        if authCookieNames.contains(name) || name.contains("token") || name.contains("auth") {
            return TokenNormalizer.isValidJWT(text) ? text : nil
        }

        return nil
    }

    private static let authCookieNames: Set<String> = [
        "token", "access_token", "accesstoken", "jwt", "authorization", "auth", "id_token",
    ]
}
