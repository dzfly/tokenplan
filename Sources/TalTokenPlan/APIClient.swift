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

    func fetchTodayUsage(completion: @escaping (Result<UsageResponse, APIError>) -> Void) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        let startMs = String(Int64(start.timeIntervalSince1970 * 1000))
        let endMs = String(Int64(now.timeIntervalSince1970 * 1000))
        request("codingPlan/usage", queryItems: [
            URLQueryItem(name: "startTime", value: startMs),
            URLQueryItem(name: "endTime", value: endMs),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: "5"),
        ], completion: completion)
    }
}

// data.costSummary + data.tokenUsage
struct BillingData: Decodable {
    let costSummary: CostSummary
    let tokenUsage: TokenUsage

    struct CostSummary: Decodable {
        let used: Double
        let limit: Double
        let remaining: Double
        let usageRatio: Double?
    }
    struct TokenUsage: Decodable {
        let totalTokens: Int64?
        let inputTokens: Int64?
        let outputTokens: Int64?
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
        let tokenUsage: ItemTokenUsage?

        struct ItemTokenUsage: Decodable {
            let totalTokens: Int64?
        }
    }
}

private struct APIResponse<T: Decodable>: Decodable {
    let code: Int?
    let msg: String?
    let data: T?
}
