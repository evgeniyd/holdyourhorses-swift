
import XCTest
import HoldYourHorses

protocol HTTPClient {
    typealias Result = Swift.Result<(Data, HTTPURLResponse), Error>

    func get(from url: URL, completion: @escaping (HTTPClient.Result) -> Void)
}

final class RateLimiter: HTTPClient {

    let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    // MARK: HTTPClient

    func get(from url: URL, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {

    }
}

final class TestCase: XCTestCase {

    func test_init_doesNotRequest() {
        let client = HTTPClientSpy()
        let sut = RateLimiter(client: client)
        XCTAssertTrue(client.requests.isEmpty, "Expects an empty requests list ")
    }

    private class HTTPClientSpy: HTTPClient {
        var requests: [URL] = []

        func get(from url: URL, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
            requests.append(url)
        }
    }
}
