
import Foundation

public final class TokenBucketRateLimiter: HTTPClient {

    private let client: HTTPClient

    private var tokens: Int
    private let maxTokens: Int
    private var lastRequestTime: Date
    private let tokenRefreshRate: TimeInterval
    private let getCurrentDate: () -> Date

    public init(client: HTTPClient, maxTokens: Int = 3, tokenRefreshRate: TimeInterval = 1.0, currentDateProvider: @escaping (() -> Date) = Date.init) {
        self.client = client
        self.maxTokens = maxTokens
        self.tokenRefreshRate = tokenRefreshRate
        self.tokens = maxTokens
        self.getCurrentDate = currentDateProvider
        self.lastRequestTime = currentDateProvider()
    }

    private func shouldAllowRequest() -> Bool {
        refreshTokens()

        guard tokens > 0 else {
            return false
        }

        tokens -= 1
        return true
    }

    private func refreshTokens() {
        let now = getCurrentDate()
        let elapsed = now.timeIntervalSince(lastRequestTime)
        if elapsed > tokenRefreshRate {
            let extraTokens = Int(elapsed / tokenRefreshRate) * maxTokens
            tokens = min(maxTokens, tokens + extraTokens)
            lastRequestTime = now
        }
    }

    // MARK: HTTPClient

    public func get(from url: URL, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        if shouldAllowRequest() {
            client.get(from: url, completion: completion)
        } else {
            let error = NSError(domain: "RateLimiterError", code: 0)
            completion(.failure(error))
        }
    }
}
