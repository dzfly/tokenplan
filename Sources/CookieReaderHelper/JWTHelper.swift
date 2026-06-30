import Foundation

enum JWTHelper {
    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - base64.count % 4
        if padding < 4 { base64 += String(repeating: "=", count: padding) }
        return Data(base64Encoded: base64)
    }

    static func decodePayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let data = base64URLDecode(String(parts[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func isStructurallyValid(_ jwt: String) -> Bool {
        guard jwt.hasPrefix("eyJ") else { return false }
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        guard base64URLDecode(String(parts[0])) != nil else { return false }
        return decodePayload(jwt) != nil
    }

    static func expirationDate(_ jwt: String) -> Date? {
        guard let payload = decodePayload(jwt),
              let exp = payload["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func isExpired(_ jwt: String, leeway: TimeInterval = 30) -> Bool {
        guard let exp = expirationDate(jwt) else { return false }
        return Date().addingTimeInterval(leeway) >= exp
    }

    static func jwtClaimSummary(_ jwt: String) -> String {
        guard let payload = decodePayload(jwt) else { return "payload 不可解析" }
        let exp = expirationDescription(jwt)
        let iss = payload["iss"] as? String ?? "-"
        let aud = payload["aud"].map { String(describing: $0) } ?? "-"
        return "exp=\(exp), iss=\(iss), aud=\(aud)"
    }

    static func expirationDescription(_ jwt: String) -> String {
        guard let exp = expirationDate(jwt) else { return "无 exp 字段" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = .current
        let label = isExpired(jwt) ? "已过期" : "有效"
        return "\(fmt.string(from: exp)) (\(label))"
    }

    static func extractFromText(_ text: String) -> String? {
        guard let range = text.range(of: "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+", options: .regularExpression) else {
            return nil
        }
        let jwt = String(text[range])
        return isStructurallyValid(jwt) ? jwt : nil
    }
}
