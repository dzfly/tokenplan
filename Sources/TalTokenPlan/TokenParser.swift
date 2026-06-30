import Foundation

enum TokenParser {
    static func parse(_ raw: String) -> String? {
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

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, text.hasPrefix("eyJ"), text.count >= 20 else { return nil }
        return text
    }

    static func isExpired(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - base64.count % 4
        if padding < 4 { base64 += String(repeating: "=", count: padding) }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else { return false }
        return Date().addingTimeInterval(30) >= Date(timeIntervalSince1970: exp)
    }
}
