import XCTest
@testable import StudyCore

final class NetworkTests: XCTestCase {
    func testHTTPErrorsShowExactCodesAndDistinguishCauses() {
        for code in [400, 401, 402, 403, 404, 408, 413, 429, 500, 502, 503, 504, 418] {
            XCTAssertTrue(StudyError.http(code).localizedDescription.contains("HTTP \(code)"))
        }
        XCTAssertTrue(StudyError.http(402).localizedDescription.contains("크레딧"))
        XCTAssertTrue(StudyError.http(413).localizedDescription.contains("크기"))
        XCTAssertTrue(StudyError.http(502).localizedDescription.contains("게이트웨이"))
        XCTAssertFalse(StudyError.http(418).localizedDescription.contains("서버 오류"))
    }

    private func client(status: Int = 200, data: Data = Data(), error: URLError? = nil) -> OpenAIClient {
        StubURLProtocol.handler = { request in
            if let error { throw error }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OpenAIClient(session: URLSession(configuration: configuration))
    }

    func testSuccessfulHTTPResponse() async throws {
        let client = client(data: try envelope())
        let result = try await client.analyze(jpeg: Data([1]), settings: .init(apiKey: "test"))
        XCTAssertEqual(result.results.first?.answer, "3번")
    }

    func testHTTPFailuresRemainOperationalErrors() async {
        for code in [400, 401, 403, 404, 429, 500, 503] {
            let client = client(status: code, data: Data("sensitive error body".utf8))
            do {
                _ = try await client.analyze(jpeg: Data([1]), settings: .init(apiKey: "test"))
                XCTFail("Expected error \(code)")
            } catch {
                XCTAssertEqual(error as? StudyError, .http(code))
                XCTAssertFalse(error.localizedDescription.contains("sensitive"))
            }
        }
    }

    func testBillingQuotaIsDistinctFromRateLimitAndDoesNotExposeBody() async {
        for field in ["code", "type"] {
            let data = try! JSONSerialization.data(withJSONObject: ["error": [field: "insufficient_quota", "message": "sensitive key and request"]])
            do {
                _ = try await client(status: 429, data: data).analyze(jpeg: Data([1]), settings: .init(apiKey: "test"))
                XCTFail("Expected billing error")
            } catch {
                XCTAssertEqual(error as? StudyError, .quotaExceeded)
                XCTAssertTrue(error.localizedDescription.contains("크레딧"))
                XCTAssertFalse(error.localizedDescription.contains("sensitive"))
            }
        }
        let data = Data(#"{"error":{"code":"rate_limit_exceeded","message":"sensitive request"}}"#.utf8)
        do {
            _ = try await client(status: 429, data: data).analyze(jpeg: Data([1]), settings: .init(apiKey: "test"))
            XCTFail("Expected rate limit")
        } catch { XCTAssertEqual(error as? StudyError, .http(429)) }
    }

    func testTimeoutAndOfflineErrors() async {
        for (code, expected) in [(URLError.timedOut, StudyError.timeout), (.notConnectedToInternet, .network)] {
            do {
                _ = try await client(error: URLError(code)).analyze(jpeg: Data([1]), settings: .init(apiKey: "test"))
                XCTFail("Expected network error")
            } catch { XCTAssertEqual(error as? StudyError, expected) }
        }
    }

    func testTransportCancellationIsNotSpokenAsFailure() async {
        do {
            _ = try await client(error: URLError(.cancelled)).analyze(jpeg: Data([1]), settings: .init(apiKey: "test"))
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
