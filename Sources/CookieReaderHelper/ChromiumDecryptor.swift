import CommonCrypto
import Foundation
import Security

enum ChromiumDecryptor {
    static func keychainPassword(service: String, account: String) -> String? {
        if let password = readKeychain(service: service, account: account) {
            return password
        }
        let fallbacks: [(String, String)] = [
            ("Tabbit Browser Safe Storage", "Tabbit Browser"),
            ("Tabbit Safe Storage", "Tabbit"),
            ("Chromium Safe Storage", "Chromium"),
        ]
        for (svc, acct) in fallbacks where svc != service || acct != account {
            if let password = readKeychain(service: svc, account: acct) {
                return password
            }
        }
        return nil
    }

    private static func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deriveKey(password: String) -> Data {
        let passwordData = Data(password.utf8)
        let salt = Data("saltysalt".utf8)
        var derived = Data(count: 16)
        derived.withUnsafeMutableBytes { derivedBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    _ = CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        16
                    )
                }
            }
        }
        return derived
    }

    /// 解密 Chromium Cookie 的 encrypted_value，返回 JWT 或明文 token
    static func decryptCookieValue(_ encrypted: Data, password: String) -> String? {
        guard let decrypted = decryptToData(encrypted, password: password) else { return nil }

        let skipOffsets = [0, 16, 32, 48]
        for skip in skipOffsets {
            guard decrypted.count > skip else { continue }
            let slice = Data(decrypted.dropFirst(skip))

            if let jwt = extractEmbeddedToken(from: slice), JWTHelper.isStructurallyValid(jwt) {
                return jwt
            }

            if let text = String(data: slice, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let token = TokenNormalizer.parseCloudAuthorization(trimmed) {
                    return token
                }
            }
        }
        return nil
    }

    private static func decryptToData(_ encrypted: Data, password: String) -> Data? {
        guard !encrypted.isEmpty else { return nil }
        var payload = encrypted
        if payload.count >= 3, let prefix = String(data: payload.prefix(3), encoding: .utf8), prefix == "v10" || prefix == "v11" {
            payload = payload.dropFirst(3)
        }
        return aes128CBCDecrypt(payload, key: deriveKey(password: password))
    }

    private static func extractEmbeddedToken(from data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
            if let jwt = JWTHelper.extractFromText(text) { return jwt }
            if let bearerRange = text.range(of: "Bearer\\s+[A-Za-z0-9._-]+", options: .regularExpression) {
                let bearer = String(text[bearerRange]).replacingOccurrences(of: "^Bearer\\s+", with: "", options: .regularExpression)
                if JWTHelper.isStructurallyValid(bearer) { return bearer }
            }
        }
        return nil
    }

    private static func aes128CBCDecrypt(_ data: Data, key: Data) -> Data? {
        let iv = Data(repeating: 0x20, count: 16)
        var outLength = 0
        let bufferSize = data.count + kCCBlockSizeAES128
        var output = Data(count: bufferSize)
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outBytes.baseAddress, bufferSize,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.count = outLength
        return pkcs7Unpad(output)
    }

    private static func pkcs7Unpad(_ data: Data) -> Data? {
        guard let last = data.last, last > 0, last <= 16 else { return data }
        let pad = Int(last)
        guard data.count >= pad else { return nil }
        for i in (data.count - pad)..<data.count where data[i] != last { return data }
        return data.dropLast(pad)
    }
}
