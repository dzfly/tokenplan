import Foundation

enum APIError: Error {
    case unauthorized
    case networkError(Error)
    case decodingError(Error)
    case unknown
}

final class APIClient {
    static let shared = APIClient()
    private let base = URL(string: "https://apx-console-api.tal.com")!
    private let appId = "300002213"
    var onUnauthorized: (() -> Void)?

    private struct AuthFailurePayload: Decodable {
        let code: Int?
        let msg: String?
    }

    private func request<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        bearerPrefix: Bool = true,
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

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                TokenStore.delete()
                DispatchQueue.main.async { self.onUnauthorized?() }
                completion(.failure(.unauthorized))
                return
            }
            guard let data = data else {
                completion(.failure(.unknown))
                return
            }
            if self.isAuthFailurePayload(data) {
                TokenStore.delete()
                DispatchQueue.main.async { self.onUnauthorized?() }
                completion(.failure(.unauthorized))
                return
            }
            do {
                let wrapper = try JSONDecoder().decode(APIResponse<T>.self, from: data)
                if let d = wrapper.data {
                    completion(.success(d))
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

    private func isAuthFailurePayload(_ data: Data) -> Bool {
        guard let payload = try? JSONDecoder().decode(AuthFailurePayload.self, from: data) else {
            return false
        }
        if payload.code == 401 || payload.code == 403 { return true }
        let msg = payload.msg?.lowercased() ?? ""
        return msg.contains("未登录") || msg.contains("登录") || msg.contains("token") || msg.contains("auth")
    }

    func fetchBilling(bearerPrefix: Bool = true, completion: @escaping (Result<BillingData, APIError>) -> Void) {
        request("codingPlan/billing", bearerPrefix: bearerPrefix, completion: completion)
    }

    func fetchChannelList(completion: @escaping (Result<ChannelListResponse, APIError>) -> Void) {
        request("codingPlan/channelList", completion: completion)
    }

    func fetchRecentUsage(
        pageSize: Int = 10,
        maxLookbackDays: Int = 30,
        completion: @escaping (Result<UsageResponse, APIError>) -> Void
    ) {
        fetchUsage(dayOffset: 0, pageSize: pageSize, maxLookbackDays: maxLookbackDays, completion: completion)
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
        request("codingPlan/usage", queryItems: [
            URLQueryItem(name: "startTime", value: startMs),
            URLQueryItem(name: "endTime", value: endMs),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ], completion: { (result: Result<UsageResponse, APIError>) in
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
        })
    }

    private static func hasUsageData(_ response: UsageResponse) -> Bool {
        !(response.list ?? []).isEmpty
    }
}

// data.costSummary + data.tokenUsage
struct BillingData: Decodable {
    let costSummary: CostSummary
    let tokenUsage: TokenUsageDetail

    struct CostSummary: Decodable {
        let used: Double
        let limit: Double
        let remaining: Double
        let usageRatio: Double?
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

    var listSortedByRequestTimeDesc: [UsageItem] {
        (list ?? []).sorted { ($0.requestTime ?? 0) > ($1.requestTime ?? 0) }
    }

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
