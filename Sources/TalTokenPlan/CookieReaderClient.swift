import Foundation

enum CookieReaderError: LocalizedError {
    case helperMissing
    case helperFailed(code: Int32, message: String)
    case helperTimedOut
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "未找到 Cookie 读取工具，请重新安装 Token Plan"
        case .helperFailed(_, let message):
            return message
        case .helperTimedOut:
            return "读取浏览器凭证超时，请确认浏览器已打开后重试"
        case .invalidOutput:
            return "Cookie 读取工具返回了无效凭证"
        }
    }

    var needsFullDiskAccess: Bool {
        if case .helperFailed(let code, _) = self { return code == 2 }
        return false
    }
}

enum CookieReaderClient {
    private static let helperTimeout: TimeInterval = 12

    static func bundledHelperURL() -> URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CookieReaderHelper")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func fetchToken(completion: @escaping (Result<String, CookieReaderError>) -> Void) {
        runHelper(arguments: [], completion: completion)
    }

    static func fetchDiagnose(completion: @escaping (String) -> Void) {
        runHelper(arguments: ["--diagnose"]) { result in
            switch result {
            case .success:
                completion("")
            case .failure(.helperFailed(_, let message)):
                completion(message)
            case .failure:
                completion("诊断失败")
            }
        }
    }

    private static func runHelper(arguments: [String], completion: @escaping (Result<String, CookieReaderError>) -> Void) {
        guard let helperURL = bundledHelperURL() else {
            completion(.failure(.helperMissing))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = helperURL
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let completionLock = NSLock()
            var didComplete = false
            func finish(_ result: Result<String, CookieReaderError>) {
                completionLock.lock()
                guard !didComplete else {
                    completionLock.unlock()
                    return
                }
                didComplete = true
                completionLock.unlock()
                DispatchQueue.main.async {
                    completion(result)
                }
            }

            process.terminationHandler = { process in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if arguments.contains("--diagnose") {
                    let message = errText.isEmpty ? "诊断无输出" : errText
                    if process.terminationStatus == 0 {
                        finish(.success(message))
                    } else {
                        finish(.failure(.helperFailed(code: process.terminationStatus, message: message)))
                    }
                    return
                }

                guard process.terminationStatus == 0 else {
                    let message = errText.isEmpty
                        ? "Cookie 读取失败 (code \(process.terminationStatus))"
                        : errText
                    finish(.failure(.helperFailed(code: process.terminationStatus, message: message)))
                    return
                }

                guard let raw = String(data: outData, encoding: .utf8),
                      let token = TokenParser.parse(raw) else {
                    finish(.failure(.invalidOutput))
                    return
                }
                finish(.success(token))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(.helperFailed(code: -1, message: "无法启动 Cookie 读取工具：\(error.localizedDescription)")))
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.helperTimeout) {
                completionLock.lock()
                let shouldTerminate = !didComplete && process.isRunning
                completionLock.unlock()
                guard shouldTerminate else { return }

                process.terminate()
                finish(.failure(.helperTimedOut))
            }
        }
    }
}
