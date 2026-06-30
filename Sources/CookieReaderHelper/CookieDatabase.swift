import Foundation
import SQLite3

enum CookieDatabase {
    /// 复制 Chromium Cookies 数据库（含 WAL/SHM），避免浏览器运行时读到不完整数据
    static func openReadonlyCopy(from cookiesPath: URL) -> OpaquePointer? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenplan-cookies-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let fileName = cookiesPath.lastPathComponent
        let parentDir = cookiesPath.deletingLastPathComponent()
        let suffixes = ["", "-wal", "-shm"]

        for suffix in suffixes {
            let source = parentDir.appendingPathComponent(fileName + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = tempDir.appendingPathComponent(fileName + suffix)
            guard (try? FileManager.default.copyItem(at: source, to: destination)) != nil else {
                return nil
            }
        }

        let tempDB = tempDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: tempDB.path) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempDB.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        return db
    }
}
