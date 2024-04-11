
import XCTest
import HoldYourHorses

final class TokenBucketRateLimiterTests: XCTestCase {

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
        let exp = sendRequestExpectedToCompleteWithFailure(sut)
        waitForExpectations(timeout: 0.1)
    }

    func test_getFromURL_requestsClientOnceWhenTwoRequestsSentSimultaneously() {
        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: 1.0, currentDateProvider: getSameDateProvider())

        sut.get(from: getURL()) { _ in }
        sut.get(from: getURL()) { _ in }

        XCTAssertEqual(client.requests.count, 1)
    }

    func test_getFromURL_failsWithErrorOnceWhenTwoRequestsSentSimultaneously() {
        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: 1.0, currentDateProvider: getSameDateProvider())

        let exp1 = sendRequestExpectedToCompleteWithSuccess(sut)
        let exp2 = sendRequestExpectedToCompleteWithFailure(sut)

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)
    }

    func test_getFromURL_requestsClientMultipleTimesWhenRequestsSentSimultaneouslyIsEqualToMaxTokens() {
        let (client, sut) = makeSUT(maxTokens: 2, tokenRefreshRate: 1.0, currentDateProvider: getSameDateProvider())
        let exp1 = sendRequestExpectedToCompleteWithSuccess(sut)
        let exp2 = sendRequestExpectedToCompleteWithSuccess(sut)

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)
    }

    func test_getFromURL_requestsClientMultipleTimesWhenRequestsSentSlowerThanTokenRefreshRate() {
        let timeBox = Box<TimeInterval>(0)
        let dateProvider = { [timeBox] in
            return Date(timeIntervalSince1970: timeBox.value)
        }
        let tokenRefreshRate = 1.0
        let nextTimeInterval = 1.1

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: tokenRefreshRate, currentDateProvider: dateProvider)

        let exp1 = sendRequestExpectedToCompleteWithSuccess(sut)
        timeBox.value += nextTimeInterval
        let exp2 = sendRequestExpectedToCompleteWithSuccess(sut)

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)
    }

    func test_getFromURL_requestsClientOnceWhenRequestsSentFasterThanTokenRefreshRate() {
        let timeBox = Box<TimeInterval>(0)
        let dateProvider = { [timeBox] in
            return Date(timeIntervalSince1970: timeBox.value)
        }

        let tokenRefreshRate = 1.0
        let nextTimeInterval = 0.9

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: tokenRefreshRate, currentDateProvider: dateProvider)

        let exp1 = sendRequestExpectedToCompleteWithSuccess(sut)
        timeBox.value += nextTimeInterval
        let exp2 = sendRequestExpectedToCompleteWithFailure(sut)

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)
    }

    func test_getFromURL_requestsClientOnceTimesWhenRequestsSentEqualToTokenRefreshRate() {
        let timeBox = Box<TimeInterval>(0)
        let dateProvider = { [timeBox] in
            return Date(timeIntervalSince1970: timeBox.value)
        }

        let tokenRefreshRate = 1.0
        let nextTimeInterval = 1.0

        let (client, sut) = makeSUT(maxTokens: 1, tokenRefreshRate: tokenRefreshRate, currentDateProvider: dateProvider)

        let exp1 = sendRequestExpectedToCompleteWithSuccess(sut)
        timeBox.value += nextTimeInterval
        let exp2 = sendRequestExpectedToCompleteWithFailure(sut)

        client.completeAllRequests()

        wait(for: [exp1, exp2], timeout: 0.1)
    }

    /*

2 tokens per 1 sec

          req.1 (OK)               req.2 (OK)               req.3 (OK)     req.4 (OK)    req.5 (FAIL)              req.6 (OK)
          V                        V                        V              V              V                        V
tokens: 2 1    1    1    1    1    0    0    0    0    0    1    1    1    0    0    0    0    0    0    0    0    1
          |----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|
          0.1  0.2  0.3  0.4  0.5  0.6  0.7  0.8  0.9  1.0  1.1  1.2  1.3  1.4  1.5  1.6  1.7  1.8  1.9  2.0  2.1  2.2
     */

    func test_getFromURL_requestRateAndTokenRefreshRateMatchesExpectations() {
        let timeBox = Box<TimeInterval>(0)
        let dateProvider = { [timeBox] in
            return Date(timeIntervalSince1970: timeBox.value)
        }
        let tokenRefreshRate = 1.0
        let maxTokens = 2

        let (client, sut) = makeSUT(maxTokens: maxTokens, tokenRefreshRate: tokenRefreshRate, currentDateProvider: dateProvider)

        let exp1 = sendRequestExpectedToCompleteWithSuccess(sut)
        timeBox.value += 0.6 // 0.6
        let exp2 = sendRequestExpectedToCompleteWithSuccess(sut)
        timeBox.value += 0.5 // 1.1
        let exp3 = sendRequestExpectedToCompleteWithSuccess(sut)
        timeBox.value += 0.3 // 1.4
        let exp4 = sendRequestExpectedToCompleteWithSuccess(sut)
        timeBox.value += 0.3 // 1.7
        let exp5 = sendRequestExpectedToCompleteWithFailure(sut)
        timeBox.value += 0.5 // 2.2
        let exp6 = sendRequestExpectedToCompleteWithSuccess(sut)

        client.completeAllRequests()

        waitForExpectations(timeout: 0.1)
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

    private func sendRequestExpectedToCompleteWithSuccess(_ sut: TokenBucketRateLimiter,
                                                          file: StaticString = #filePath,
                                                          line: UInt = #line) -> XCTestExpectation {
        let exp = expectation(description: "Did received result")
        var receivedSuccessCount = 0
        sut.get(from: getURL()) { result in
            switch result {
                case .success: break
                case .failure:
                    XCTFail("Expected to complete with success. Completed with failure instead", file: file, line: line)
            }
            exp.fulfill()
        }
        return exp 
    }

    private func sendRequestExpectedToCompleteWithFailure(_ sut: TokenBucketRateLimiter,
                                                          file: StaticString = #filePath,
                                                          line: UInt = #line) -> XCTestExpectation {
        let exp = expectation(description: "Did received result")
        sut.get(from: getURL()) { result in
            var receivedErrorCount = 0
            switch result {
                case .success:
                    XCTFail("Expected to complete with failure. Completed with success instead", file: file, line: line)
                case .failure: break
            }
            exp.fulfill()
        }
        return exp
    }

    private final class Box<T> {
        var value: T
        init(_ value: T) {
            self.value = value
        }
    }

    private func makeSUT(maxTokens: Int = 3, tokenRefreshRate: TimeInterval = 1.0, currentDateProvider: @escaping (() -> Date) = Date.init, file: StaticString = #file, line: UInt = #line) -> (client: HTTPClientSpy, sut: TokenBucketRateLimiter) {
        let client = HTTPClientSpy()
        let sut = TokenBucketRateLimiter(client: client, maxTokens: maxTokens, tokenRefreshRate: tokenRefreshRate, currentDateProvider: currentDateProvider)
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
