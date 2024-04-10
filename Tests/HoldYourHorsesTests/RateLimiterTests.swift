
import XCTest
import HoldYourHorses

protocol HTTPClient {
    typealias Result = Swift.Result<(Data, HTTPURLResponse), Error>

    func get(from url: URL, completion: @escaping (HTTPClient.Result) -> Void)
}

final class RateLimiter: HTTPClient {

    private let client: HTTPClient

    private var tokens: Int
    private let maxTokens: Int
    private var lastRequestTime: Date
    private let tokenRefreshRate: TimeInterval
    private let getCurrentDate: () -> Date

    init(client: HTTPClient, maxTokens: Int = 3, tokenRefreshRate: TimeInterval = 1.0, currentDateProvider: @escaping (() -> Date) = Date.init) {
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

    func get(from url: URL, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        if shouldAllowRequest() {
            client.get(from: url, completion: completion)
        }
    }
}

final class TestCase: XCTestCase {

    func test_init_doesNotRequest() {
        let (client, _) = makeSUT()
        XCTAssertTrue(client.requests.isEmpty, "Expects an empty requests list ")
    }

    func test_getFromURL_requestsClientGetFromURL() {
        var dateProvider = {
            return Date(timeIntervalSince1970: 0)
        }

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: 1.0, currentDateProvider: dateProvider)
        sut.get(from: getURL()) { _ in }

        XCTAssertEqual(client.requests.count, 1)
    }

    func test_getFromURL_returnsErrorWhenInitWithZeroTokens() {
        var dateProvider = {
            return Date(timeIntervalSince1970: 0)
        }

        let (client, sut) = makeSUT(maxTokens: 0, tokenRefreshRate: 1.0, currentDateProvider: dateProvider)
        sut.get(from: getURL()) { _ in }

        XCTAssertEqual(client.requests.count, 0)
    }

    // MARK: Helpers

    private class HTTPClientSpy: HTTPClient {
        var requests: [URL] = []

        func get(from url: URL, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
            requests.append(url)
        }
    }

    private func makeSUT(maxTokens: Int = 3, tokenRefreshRate: TimeInterval = 1.0, currentDateProvider: @escaping (() -> Date) = Date.init, file: StaticString = #file, line: UInt = #line) -> (client: HTTPClientSpy, sut: RateLimiter) {
        let client = HTTPClientSpy()
        let sut = RateLimiter(client: client, maxTokens: maxTokens, tokenRefreshRate: tokenRefreshRate, currentDateProvider: currentDateProvider)
        trackForMemoryLeaks(client, file: file, line: line)
        trackForMemoryLeaks(sut, file: file, line: line)
        return (client, sut)
    }

    private func getURL() -> URL {
        return URL(string: "https://any-url.com")!
    }
}
