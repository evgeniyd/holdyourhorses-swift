
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

    func test_init_doesNotRequestClient() {
        let (client, _) = makeSUT()
        XCTAssertTrue(client.requests.isEmpty, "Expects an empty requests list ")
    }

    func test_getFromURL_requestsClient() {
        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: 1.0, currentDateProvider: getSameDateProvider())
        sut.get(from: getURL()) { _ in }

        XCTAssertEqual(client.requests.count, 1)
    }

    func test_getFromURL_doesNotRequestsClientWhenSUTInitWithZeroTokens() {
        let (client, sut) = makeSUT(maxTokens: 0, tokenRefreshRate: 1.0, currentDateProvider: getSameDateProvider())
        sut.get(from: getURL()) { _ in }

        XCTAssertEqual(client.requests.count, 0)
    }

    func test_getFromURL_failsWithErrorWhenSUTInitWithZeroTokens() {
        let (_, sut) = makeSUT(maxTokens: 0, tokenRefreshRate: 1.0, currentDateProvider: getSameDateProvider())
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
        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: 1.0, currentDateProvider: getSameDateProvider())

        sut.get(from: getURL()) { _ in }
        sut.get(from: getURL()) { _ in }

        XCTAssertEqual(client.requests.count, 1)
    }

    func test_getFromURL_failsWithErrorOnceWhenTwoRequestsSentSimultaneously() {
        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: 1.0, currentDateProvider: getSameDateProvider())
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

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)

        XCTAssertEqual(receivedError.count, 1)
    }

    func test_getFromURL_requestsClientMultipleTimesWhenRequestsSentSimultaneouslyIsEqualToMaxTokens() {
        let (client, sut) = makeSUT(maxTokens: 2, tokenRefreshRate: 1.0, currentDateProvider: getSameDateProvider())
        let exp1 = expectation(description: "Did received result")
        let exp2 = expectation(description: "Did received result")
        var receivedResponsesCount = 0

        sut.get(from: getURL()) { result in
            switch result {
                case .success:
                    receivedResponsesCount += 1
                case .failure: break
            }
            exp1.fulfill()
        }

        sut.get(from: getURL()) { result in
            switch result {
                case .success:
                    receivedResponsesCount += 1
                case .failure: break
            }
            exp2.fulfill()
        }

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)

        XCTAssertEqual(receivedResponsesCount, 2)
    }

    func test_getFromURL_requestsClientMultipleTimesWhenRequestsSentSlowerThanTokenRefreshRate() {
        let timeBox = Box<TimeInterval>(0)
        let dateProvider = { [timeBox] in
            return Date(timeIntervalSince1970: timeBox.value)
        }
        let tokenRefreshRate = 1.0
        let nextTimeInterval = 1.1

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: tokenRefreshRate, currentDateProvider: dateProvider)
        let exp1 = expectation(description: "Did received result")
        let exp2 = expectation(description: "Did received result")
        var receivedResponsesCount = 0

        sut.get(from: getURL()) { result in
            switch result {
                case .success:
                    receivedResponsesCount += 1
                case .failure: break
            }
            exp1.fulfill()
        }

        timeBox.value += nextTimeInterval

        sut.get(from: getURL()) { result in
            switch result {
                case .success:
                    receivedResponsesCount += 1
                case .failure: break
            }
            exp2.fulfill()
        }

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)

        XCTAssertEqual(receivedResponsesCount, 2)
    }

    func test_getFromURL_requestsClientOnceWhenRequestsSentFasterThanTokenRefreshRate() {
        let timeBox = Box<TimeInterval>(0)
        let  dateProvider = { [timeBox] in
            return Date(timeIntervalSince1970: timeBox.value)
        }

        let tokenRefreshRate = 1.0
        let nextTimeInterval = 0.9

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: tokenRefreshRate, currentDateProvider: dateProvider)
        let exp1 = expectation(description: "Did received result")
        let exp2 = expectation(description: "Did received result")
        var receivedResponsesCount = 0
        var receivedErrorCount = 0

        sut.get(from: getURL()) { result in
            switch result {
                case .success:
                    receivedResponsesCount += 1
                case .failure:
                    receivedErrorCount += 1
            }
            exp1.fulfill()
        }

        timeBox.value += nextTimeInterval

        sut.get(from: getURL()) { result in
            switch result {
                case .success:
                    receivedResponsesCount += 1
                case .failure:
                    receivedErrorCount += 1
            }
            exp2.fulfill()
        }

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)

        XCTAssertEqual(receivedResponsesCount, 1)
        XCTAssertEqual(receivedErrorCount, 1)
    }

    func test_getFromURL_requestsClientOnceTimesWhenRequestsSentEqualToTokenRefreshRate() {
        let timeBox = Box<TimeInterval>(0)
        let  dateProvider = { [timeBox] in
            return Date(timeIntervalSince1970: timeBox.value)
        }

        let tokenRefreshRate = 1.0
        let nextTimeInterval = 1.0

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: tokenRefreshRate, currentDateProvider: dateProvider)
        let exp1 = expectation(description: "Did received result")
        let exp2 = expectation(description: "Did received result")
        var receivedResponsesCount = 0
        var receivedErrorCount = 0

        sut.get(from: getURL()) { result in
            switch result {
                case .success:
                    receivedResponsesCount += 1
                case .failure:
                    receivedErrorCount += 1
            }
            exp1.fulfill()
        }

        timeBox.value += nextTimeInterval

        sut.get(from: getURL()) { result in
            switch result {
                case .success:
                    receivedResponsesCount += 1
                case .failure:
                    receivedErrorCount += 1
            }
            exp2.fulfill()
        }

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)

        XCTAssertEqual(receivedResponsesCount, 1)
        XCTAssertEqual(receivedErrorCount, 1)
    }

    // MARK: Helpers

    private class HTTPClientSpy: HTTPClient {

        var requests: [(url: URL, completion: (Result<(Data, HTTPURLResponse), Error>) -> Void)] = []

        func get(from url: URL, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
            requests.append( (url, completion) )
        }

        func completeAllRequests(with data: Data = Data()) {
            for request in requests {
                let response = createHTTPURLResponse(request.url)
                request.completion( .success((data, response)) )
            }
        }

        private func createHTTPURLResponse(_ url: URL) -> HTTPURLResponse {
            let code = 200
            let response = HTTPURLResponse(url: url,
                                           statusCode: code,
                                           httpVersion: nil,
                                           headerFields: nil)!
            return response
        }
    }

    private final class Box<T> {
        var value: T
        init(_ value: T) {
            self.value = value
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

    private func getSameDateProvider() -> (() -> Date) {
        let dateProvider = {
            return Date(timeIntervalSince1970: 0)
        }
        return dateProvider
    }
}
