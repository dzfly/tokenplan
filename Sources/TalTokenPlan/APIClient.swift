import Foundation

enum APIError: Error {
    case unauthorized
    case networkError(Error)
    case decodingError(Error)
    case unknown
}

final class APIClient {
    static let shared = APIClient()
    static let requestTimeout: TimeInterval = 15
    private let base = URL(string: "https://apx-console-api.tal.com")!
    private let appId = "300002213"

    private func request<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        bearerPrefix: Bool? = nil,
        completion: @escaping (Result<T, APIError>) -> Void
    ) {
        let preferredBearer = bearerPrefix ?? TokenStore.useBearerPrefix
        performRequest(path, queryItems: queryItems, bearerPrefix: preferredBearer) { (result: Result<T, APIError>) in
            switch result {
            case .failure(.unauthorized) where preferredBearer:
                self.performRequest(path, queryItems: queryItems, bearerPrefix: false) { (retry: Result<T, APIError>) in
                    switch retry {
                    case .success:
                        TokenStore.useBearerPrefix = false
                        completion(retry)
                    case .failure(.unauthorized):
                        completion(.failure(.unauthorized))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .success:
                TokenStore.useBearerPrefix = preferredBearer
                completion(result)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func performRequest<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        bearerPrefix: Bool,
        completion: @escaping (Result<T, APIError>) -> Void
    ) {
        guard let token = TokenStore.load() else {
            completion(.failure(.unauthorized))
            return
        }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "appId", value: appId)] + queryItems
        var req = URLRequest(url: components.url!)
        let authValue = bearerPrefix ? "Bearer \(token)" : token
        req.setValue(authValue, forHTTPHeaderField: "Authorization")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("https://cloud.tal.com/", forHTTPHeaderField: "Referer")
        req.setValue("https://cloud.tal.com", forHTTPHeaderField: "Origin")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        req.timeoutInterval = Self.requestTimeout

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                completion(.failure(.unauthorized))
                return
            }
            guard let data = data else {
                completion(.failure(.unknown))
                return
            }
            do {
                let wrapper = try JSONDecoder().decode(APIResponse<T>.self, from: data)
                if let d = wrapper.data {
                    completion(.success(d))
                } else if self.isAuthFailure(code: wrapper.code, msg: wrapper.msg) {
                    completion(.failure(.unauthorized))
                } else {
                    completion(.failure(.unknown))
                }
            } catch {
                do {
                    let direct = try JSONDecoder().decode(T.self, from: data)
                    completion(.success(direct))
                } catch let e2 {
                    completion(.failure(.decodingError(e2)))
                }
            }
        }.resume()
    }

    private func isAuthFailure(code: Int?, msg: String?) -> Bool {
        if code == 401 || code == 403 { return true }
        if let code, code == 0 || code == 200 { return false }
        let text = msg?.lowercased() ?? ""
        return text.contains("未登录")
            || text.contains("请先登录")
            || text.contains("not logged in")
            || text.contains("unauthorized")
            || text.contains("token expired")
            || text.contains("jwt expired")
            || text.contains("token无效")
            || text.contains("token 无效")
            || text.contains("登录已过期")
            || text.contains("登录过期")
    }

    func fetchBilling(bearerPrefix: Bool? = nil, completion: @escaping (Result<BillingData, APIError>) -> Void) {
        request("codingPlan/billing", bearerPrefix: bearerPrefix, completion: completion)
    }

    func fetchChannelList(completion: @escaping (Result<ChannelListResponse, APIError>) -> Void) {
        request("codingPlan/channelList", completion: completion)
    }

    func fetchRecentUsage(
        pageSize: Int = 500,
        maxLookbackDays: Int = 2,
        completion: @escaping (Result<UsageResponse, APIError>) -> Void
    ) {
        fetchUsage(dayOffset: 0, pageSize: pageSize, maxLookbackDays: maxLookbackDays, completion: completion)
    }

    struct DailyUsage {
        let dayStart: Date
        let items: [UsageResponse.UsageItem]
    }

    /// 并发拉取最近 days 天（含今天）的逐日用量，返回按 今天→N天前 排序。
    /// 单日失败（网络/解码）按空数据处理，不导致整体失败；401/403 时整体返回 unauthorized。
    func fetchRecentDailyUsage(
        days: Int = 7,
        completion: @escaping (Result<[DailyUsage], APIError>) -> Void
    ) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var results = [DailyUsage?](repeating: nil, count: days)
        let group = DispatchGroup()
        let lock = NSLock()
        var unauthorized = false

        for offset in 0..<days {
            let dayStart = cal.date(byAdding: .day, value: -offset, to: todayStart)!
            let end: Date = offset == 0
                ? Date()
                : dayStart.addingTimeInterval(24 * 60 * 60 - 1)
            let startMs = String(Int64(dayStart.timeIntervalSince1970 * 1000))
            let endMs = String(Int64(end.timeIntervalSince1970 * 1000))

            group.enter()
            fetchDayAllPages(startMs: startMs, endMs: endMs, pageSize: 500) { result in
                defer { group.leave() }
                switch result {
                case .success(let response):
                    lock.lock()
                    results[offset] = DailyUsage(dayStart: dayStart, items: response.list ?? [])
                    lock.unlock()
                case .failure(.unauthorized):
                    lock.lock()
                    unauthorized = true
                    lock.unlock()
                case .failure:
                    break // 单日失败按空处理（spec：单日失败记 0，整体不失败）
                }
            }
        }

        group.notify(queue: .main) {
            if unauthorized {
                completion(.failure(.unauthorized))
                return
            }
            let assembled = (0..<days).map { offset -> DailyUsage in
                if let r = results[offset] { return r }
                let day = cal.date(byAdding: .day, value: -offset, to: todayStart)!
                return DailyUsage(dayStart: day, items: [])
            }
            completion(.success(assembled))
        }
    }

    private func fetchUsage(
        dayOffset: Int,
        pageSize: Int,
        maxLookbackDays: Int,
        completion: @escaping (Result<UsageResponse, APIError>) -> Void
    ) {
        let cal = Calendar.current
        let now = Date()
        let targetDay = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: now))!
        let start = cal.startOfDay(for: targetDay)
        let end: Date
        if dayOffset == 0 {
            end = now
        } else if let nextDay = cal.date(byAdding: .day, value: 1, to: start) {
            end = nextDay.addingTimeInterval(-1)
        } else {
            completion(.failure(.unknown))
            return
        }

        let startMs = String(Int64(start.timeIntervalSince1970 * 1000))
        let endMs = String(Int64(end.timeIntervalSince1970 * 1000))
        fetchDayAllPages(startMs: startMs, endMs: endMs, pageSize: pageSize) { result in
            switch result {
            case .success(let response):
                if Self.hasUsageData(response) {
                    completion(.success(response))
                } else if dayOffset + 1 < maxLookbackDays {
                    self.fetchUsage(
                        dayOffset: dayOffset + 1,
                        pageSize: pageSize,
                        maxLookbackDays: maxLookbackDays,
                        completion: completion
                    )
                } else {
                    completion(.success(response))
                }
            case .failure(.unauthorized):
                completion(.failure(.unauthorized))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func fetchDayAllPages(
        startMs: String,
        endMs: String,
        pageSize: Int,
        completion: @escaping (Result<UsageResponse, APIError>) -> Void
    ) {
        var allItems: [UsageResponse.UsageItem] = []
        var total = 0
        var page = 1
        func fetchPage() {
            request("codingPlan/usage", queryItems: [
                URLQueryItem(name: "startTime", value: startMs),
                URLQueryItem(name: "endTime", value: endMs),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
            ], completion: { (result: Result<UsageResponse, APIError>) in
                switch result {
                case .success(let response):
                    let pageList = response.list ?? []
                    allItems.append(contentsOf: pageList)
                    if total == 0 { total = response.total ?? pageList.count }
                    if !pageList.isEmpty && allItems.count < total {
                        page += 1
                        fetchPage()
                    } else {
                        completion(.success(UsageResponse(total: total, list: allItems)))
                    }
                case .failure(.unauthorized):
                    completion(.failure(.unauthorized))
                case .failure(let error):
                    completion(.failure(error))
                }
            })
        }
        fetchPage()
    }

    private static func hasUsageData(_ response: UsageResponse) -> Bool {
        !(response.list ?? []).isEmpty
    }
}

// data.costSummary + data.tokenUsage
struct BillingData: Decodable {
    let costSummary: CostSummary
    let tokenUsage: TokenUsageDetail?

    struct CostSummary: Decodable {
        let used: Double
        let reserved: Double?
        let limit: Double
        let remaining: Double
        let usageRatio: Double?
        let maxModelUsed: Double?
        let maxModelLimit: Double?
        let maxModelRemaining: Double?
        let maxModelUsageRatio: Double?
        let maxModelPercentage: Double?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            used = try Self.decodeDouble(c, forKey: .used)
            reserved = try Self.decodeOptionalDouble(c, forKey: .reserved)
            limit = try Self.decodeDouble(c, forKey: .limit)
            remaining = try Self.decodeDouble(c, forKey: .remaining)
            usageRatio = try Self.decodeOptionalDouble(c, forKey: .usageRatio)
            maxModelUsed = try Self.decodeOptionalDouble(c, forKey: .maxModelUsed)
            maxModelLimit = try Self.decodeOptionalDouble(c, forKey: .maxModelLimit)
            maxModelRemaining = try Self.decodeOptionalDouble(c, forKey: .maxModelRemaining)
            maxModelUsageRatio = try Self.decodeOptionalDouble(c, forKey: .maxModelUsageRatio)
            maxModelPercentage = try Self.decodeOptionalDouble(c, forKey: .maxModelPercentage)
        }

        private enum CodingKeys: String, CodingKey {
            case used, reserved, limit, remaining, usageRatio
            case maxModelUsed, maxModelLimit, maxModelRemaining
            case maxModelUsageRatio, maxModelPercentage
        }

        private static func decodeDouble(
            _ c: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> Double {
            if let v = try? c.decode(Double.self, forKey: key) { return v }
            if let v = try? c.decode(Int.self, forKey: key) { return Double(v) }
            if let text = try? c.decode(String.self, forKey: key), let v = Double(text) { return v }
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "expected number")
        }

        private static func decodeOptionalDouble(
            _ c: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> Double? {
            guard c.contains(key) else { return nil }
            if (try? c.decodeNil(forKey: key)) == true { return nil }
            return try decodeDouble(c, forKey: key)
        }
    }
}

struct TokenUsageDetail: Decodable {
    let totalTokens: Int64?
    let inputTokens: Int64?
    let outputTokens: Int64?
    let cacheReadTokens: Int64?
    let cacheWriteTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case totalTokens
        case inputTokens
        case outputTokens
        case cacheReadTokens
        case cacheWriteTokens
        case cacheReadInputTokens
        case cacheCreationInputTokens
        case cacheWriteInputTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens)
        inputTokens = try container.decodeIfPresent(Int64.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int64.self, forKey: .outputTokens)
        cacheReadTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheReadTokens)
            ?? container.decodeIfPresent(Int64.self, forKey: .cacheReadInputTokens)
        cacheWriteTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheWriteTokens)
            ?? container.decodeIfPresent(Int64.self, forKey: .cacheCreationInputTokens)
            ?? container.decodeIfPresent(Int64.self, forKey: .cacheWriteInputTokens)
    }

    var cacheRead: Int64 { cacheReadTokens ?? 0 }
    var cacheWrite: Int64 { cacheWriteTokens ?? 0 }

    var hasCacheData: Bool { cacheRead > 0 || cacheWrite > 0 }

    /// 缓存命中率 = cache_read / inputTokens（Anthropic 计费语义下 inputTokens 已含 cache_read/cache_write/普通 input）
    var cacheHitRatePercent: Double? {
        let input = inputTokens ?? 0
        if input > 0 {
            return Double(cacheRead) / Double(input) * 100
        }
        return nil
    }

    static func aggregate(from items: [UsageResponse.UsageItem]) -> TokenUsageDetail {
        var total: Int64 = 0
        var input: Int64 = 0
        var output: Int64 = 0
        var cacheRead: Int64 = 0
        var cacheWrite: Int64 = 0
        for item in items {
            guard let usage = item.tokenUsage else { continue }
            total += usage.totalTokens ?? 0
            input += usage.inputTokens ?? 0
            output += usage.outputTokens ?? 0
            cacheRead += usage.cacheRead
            cacheWrite += usage.cacheWrite
        }
        return TokenUsageDetail(
            totalTokens: total,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite
        )
    }

    private init(
        totalTokens: Int64?,
        inputTokens: Int64?,
        outputTokens: Int64?,
        cacheReadTokens: Int64?,
        cacheWriteTokens: Int64?
    ) {
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }
}

struct ChannelListResponse: Decodable {
    let list: [Channel]
    struct Channel: Decodable {
        let channel: String
        let channelName: String
    }
}

struct UsageResponse: Decodable {
    let total: Int?
    let list: [UsageItem]?

    struct UsageItem: Decodable {
        let model: String?
        let costs: Double?
        let channelName: String?
        let tokenUsage: TokenUsageDetail?
        let requestTime: Int64?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            model = try container.decodeIfPresent(String.self, forKey: .model)
            costs = try container.decodeIfPresent(Double.self, forKey: .costs)
            channelName = try container.decodeIfPresent(String.self, forKey: .channelName)
            tokenUsage = try container.decodeIfPresent(TokenUsageDetail.self, forKey: .tokenUsage)
            requestTime = Self.decodeTimestamp(from: container, key: .requestTime)
        }

        private enum CodingKeys: String, CodingKey {
            case model
            case costs
            case channelName
            case tokenUsage
            case requestTime
        }

        private static func decodeTimestamp(
            from container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys
        ) -> Int64? {
            if let value = try? container.decodeIfPresent(Int64.self, forKey: key) { return value }
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
            if let text = try? container.decodeIfPresent(String.self, forKey: key) {
                if let value = Int64(text) { return value }
                if let value = Double(text) { return Int64(value) }
            }
            return nil
        }
    }
}

private struct APIResponse<T: Decodable>: Decodable {
    let code: Int?
    let msg: String?
    let data: T?
}
