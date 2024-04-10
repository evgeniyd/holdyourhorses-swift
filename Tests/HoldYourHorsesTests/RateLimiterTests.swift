
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
        } else {
            let error = NSError(domain: "RateLimiterError", code: 0)
            completion(.failure(error))
        }
    }
}

final class TestCase: XCTestCase {

    func test_init_doesNotRequest() {
        let (client, _) = makeSUT()
        XCTAssertTrue(client.requests.isEmpty, "Expects an empty requests list ")
    }

    func test_getFromURL_requestsClient() {
        let dateProvider = {
            return Date(timeIntervalSince1970: 0)
        }

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: 1.0, currentDateProvider: dateProvider)
        sut.get(from: getURL()) { _ in }

        XCTAssertEqual(client.requests.count, 1)
    }

    func test_getFromURL_doesNotRequestsClientWhenSUTInitWithZeroTokens() {
        let dateProvider = {
            return Date(timeIntervalSince1970: 0)
        }

        let (client, sut) = makeSUT(maxTokens: 0, tokenRefreshRate: 1.0, currentDateProvider: dateProvider)
        sut.get(from: getURL()) { _ in }

        XCTAssertEqual(client.requests.count, 0)
    }

    func test_getFromURL_failsWithErrorWhenSUTInitWithZeroTokens() {
        let dateProvider = {
            return Date(timeIntervalSince1970: 0)
        }

        let (_, sut) = makeSUT(maxTokens: 0, tokenRefreshRate: 1.0, currentDateProvider: dateProvider)
        let exp = expectation(description: "Did received result")
        var receivedError: Error? = nil

        sut.get(from: getURL()) { result in
            switch result {
                case let .failure(error):
                    receivedError = error
                case .success: break
            }
            exp.fulfill()
        }

        waitForExpectations(timeout: 0.1)

        XCTAssertNotNil(receivedError)
    }

    func test_getFromURL_requestsClientOnceWhenTwoRequestsSentSimultaneously() {
        let dateProvider = {
            return Date(timeIntervalSince1970: 0)
        }

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: 1.0, currentDateProvider: dateProvider)

        sut.get(from: getURL()) { _ in }
        sut.get(from: getURL()) { _ in }

        XCTAssertEqual(client.requests.count, 1)
    }

    func test_getFromURL_failsWithErrorOnceWhenTwoRequestsSentSimultaneously() {
        let  dateProvider = {
            return Date(timeIntervalSince1970: 0)
        }

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: 1.0, currentDateProvider: dateProvider)
        var receivedError: [Error] = []
        let exp1 = expectation(description: "Did received result")
        let exp2 = expectation(description: "Did received result")

        sut.get(from: getURL()) { result in
            switch result {
                case let .failure(error):
                    receivedError.append(error)
                case .success: break
            }
            exp1.fulfill()
        }

        sut.get(from: getURL()) { result in
            switch result {
                case let .failure(error):
                    receivedError.append(error)
                case .success: break
            }
            exp2.fulfill()
        }

        client.complete()

        wait(for: [exp1, exp2], timeout: 0.1)

        XCTAssertEqual(receivedError.count, 1)
    }

    // MARK: Helpers

    private class HTTPClientSpy: HTTPClient {

        var requests: [(url: URL, completion: (Result<(Data, HTTPURLResponse), Error>) -> Void)] = []

        func get(from url: URL, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
            requests.append( (url, completion) )
        }

        func complete(with data: Data = Data(), at index: Int = 0) {
            let code = 200
            let response = HTTPURLResponse(url: requests[index].url,
                                           statusCode: code,
                                           httpVersion: nil,
                                           headerFields: nil)!
            requests[index].completion( .success((data, response)) )
        }

        func complete(with error: Error, at index: Int = 0) {

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
