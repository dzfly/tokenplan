import Foundation
import SQLite3

struct ChromiumCookieSchema {
    let columns: Set<String>

    var hostColumn: String {
        columns.contains("host_key") ? "host_key" : "host"
    }

    var hasValue: Bool { columns.contains("value") }
    var hasEncryptedValue: Bool { columns.contains("encrypted_value") }

    static func detect(db: OpaquePointer) -> ChromiumCookieSchema? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(cookies)", -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }

        var columns = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cName = sqlite3_column_text(stmt, 1) else { continue }
            columns.insert(String(cString: cName))
        }
        guard columns.contains("name"),
              columns.contains("host_key") || columns.contains("host") else { return nil }
        return ChromiumCookieSchema(columns: columns)
    }

    func columnSummary() -> String {
        columns.sorted().joined(separator: ", ")
    }
}

struct CloudAuthQueryPlan {
    let sql: String
    let nameIndex: Int32
    let plainIndex: Int32?
    let encryptedIndex: Int32?
    let hostIndex: Int32
}

enum ChromiumCookieQuery {
    static func cloudAuthorizationPlan(for schema: ChromiumCookieSchema) -> CloudAuthQueryPlan {
        var selectCols: [String] = []
        var nameIndex: Int32 = 0
        var plainIndex: Int32?
        var encryptedIndex: Int32?
        var hostIndex: Int32 = 0
        var index: Int32 = 0

        selectCols.append("name")
        nameIndex = index
        index += 1

        if schema.hasValue {
            selectCols.append("value")
            plainIndex = index
            index += 1
        }
        if schema.hasEncryptedValue {
            selectCols.append("encrypted_value")
            encryptedIndex = index
            index += 1
        }

        selectCols.append(schema.hostColumn)
        hostIndex = index

        let host = schema.hostColumn
        let sql = """
            SELECT \(selectCols.joined(separator: ", ")) FROM cookies
            WHERE (\(host) = 'cloud.tal.com' OR \(host) = '.cloud.tal.com')
              AND name = 'Authorization' COLLATE NOCASE
            """

        return CloudAuthQueryPlan(
            sql: sql,
            nameIndex: nameIndex,
            plainIndex: plainIndex,
            encryptedIndex: encryptedIndex,
            hostIndex: hostIndex
        )
    }

    static func prepareCloudAuthorizationQuery(db: OpaquePointer) -> (plan: CloudAuthQueryPlan, schema: ChromiumCookieSchema)? {
        guard let schema = ChromiumCookieSchema.detect(db: db) else { return nil }
        let plan = cloudAuthorizationPlan(for: schema)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, plan.sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_finalize(stmt)
        return (plan, schema)
    }

    static func sqliteError(db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }
}

struct CookieValueRow {
    let name: String
    let host: String
    let plain: String
    let encrypted: Data?
}

enum CloudAuthorizationFetcher {
    static func fetchRows(db: OpaquePointer, plan: CloudAuthQueryPlan, password: String) -> Result<[CookieValueRow], CookieFetchError> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, plan.sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return .failure(.queryFailed(ChromiumCookieQuery.sqliteError(db: db)))
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [CookieValueRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = stringColumn(stmt, plan.nameIndex) ?? ""
            let host = stringColumn(stmt, plan.hostIndex) ?? ""
            let plain = plan.plainIndex.map { stringColumn(stmt, $0) ?? "" } ?? ""
            let encrypted = plan.encryptedIndex.flatMap { dataColumn(stmt, $0) }
            rows.append(CookieValueRow(name: name, host: host, plain: plain, encrypted: encrypted))
        }
        return .success(rows)
    }

    static func extractToken(from rows: [CookieValueRow], password: String) -> TokenExtractResult {
        var foundExpired = false
        for row in rows {
            var candidates: [String] = []
            if let encrypted = row.encrypted,
               let decrypted = ChromiumDecryptor.decryptCookieValue(encrypted, password: password) {
                candidates.append(decrypted)
            }
            if !row.plain.isEmpty { candidates.append(row.plain) }

            for raw in candidates {
                if let token = TokenExtractor.parse(raw, cookieName: row.name, host: row.host) {
                    if JWTHelper.isExpired(token) {
                        foundExpired = true
                        continue
                    }
                    return .found(token)
                }
            }
        }
        if foundExpired { return .expired }
        return rows.isEmpty ? .notFound : .invalidValue
    }

    static func inspectRows(_ rows: [CookieValueRow], password: String, indent: String) -> [String] {
        var lines: [String] = []
        if rows.isEmpty {
            lines.append("\(indent)未找到 cloud.tal.com/Authorization Cookie")
            lines.append("\(indent)请在该浏览器打开 cloud.tal.com 并完成登录")
            return lines
        }

        for (index, row) in rows.enumerated() {
            lines.append("\(indent)Cookie[\(index + 1)]: \(row.host)/\(row.name)")

            if !row.plain.isEmpty {
                if let jwt = TokenNormalizer.parseCloudAuthorization(row.plain) {
                    lines.append("\(indent)  明文: JWT=有效, \(JWTHelper.jwtClaimSummary(jwt))")
                } else {
                    lines.append("\(indent)  明文: 长度=\(row.plain.count), JWT=无效")
                }
            } else {
                lines.append("\(indent)  明文: 空")
            }

            if let encrypted = row.encrypted, !encrypted.isEmpty {
                let prefix = encrypted.count >= 3 ? (String(data: encrypted.prefix(3), encoding: .utf8) ?? "?") : "?"
                if let jwt = ChromiumDecryptor.decryptCookieValue(encrypted, password: password) {
                    lines.append("\(indent)  密文: 前缀=\(prefix), 长度=\(encrypted.count), 解密=OK, \(JWTHelper.jwtClaimSummary(jwt))")
                } else {
                    lines.append("\(indent)  密文: 前缀=\(prefix), 长度=\(encrypted.count), 解密=失败")
                }
            } else {
                lines.append("\(indent)  密文: 空")
            }
        }
        return lines
    }

    private static func stringColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_TEXT:
            guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
            return String(cString: cStr)
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
            let count = Int(sqlite3_column_bytes(stmt, index))
            return String(data: Data(bytes: bytes, count: count), encoding: .utf8)
        default:
            return nil
        }
    }

    private static func dataColumn(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: count)
    }
}

enum CookieFetchError: Error {
    case queryFailed(String)
    case schemaUnsupported(String)
}

enum TokenExtractResult {
    case found(String)
    case expired
    case notFound
    case invalidValue
}
