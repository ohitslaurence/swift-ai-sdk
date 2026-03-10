import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// An abstraction over HTTP transport used by providers.
public protocol AIHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func stream(for request: URLRequest) async throws -> AIHTTPStreamResponse
}

/// A streaming HTTP response.
public struct AIHTTPStreamResponse: Sendable {
    public let response: HTTPURLResponse
    public let body: AsyncThrowingStream<Data, any Error>

    public init(response: HTTPURLResponse, body: AsyncThrowingStream<Data, any Error>) {
        self.response = response
        self.body = body
    }
}

/// The default URLSession-backed transport scaffold.
public struct URLSessionTransport: AIHTTPTransport, Sendable {
    public init(session: URLSession = .shared) {
        _ = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        _ = request
        throw AIError.unsupportedFeature("URLSession transport is not implemented yet")
    }

    public func stream(for request: URLRequest) async throws -> AIHTTPStreamResponse {
        _ = request
        throw AIError.unsupportedFeature("URLSession streaming is not implemented yet")
    }
}

/// Shared HTTP configuration used by providers.
public struct AIProviderHTTPConfiguration: Sendable {
    public var baseURL: URL?
    public var transport: any AIHTTPTransport
    public var defaultHeaders: [String: String]

    public init(
        baseURL: URL? = nil,
        transport: any AIHTTPTransport,
        defaultHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.defaultHeaders = defaultHeaders
    }
}
