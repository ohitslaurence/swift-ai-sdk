import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Optional URLProtocol smoke-test helper.
public final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) public static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    public override class func canInit(with request: URLRequest) -> Bool {
        _ = request
        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    public override func stopLoading() {}
}
