import AICore
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A deterministic mock transport.
public struct MockTransport: AIHTTPTransport, Sendable {
    public var dataHandler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public var streamHandler: @Sendable (URLRequest) async throws -> AIHTTPStreamResponse

    public init(
        dataHandler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        streamHandler: @escaping @Sendable (URLRequest) async throws -> AIHTTPStreamResponse
    ) {
        self.dataHandler = dataHandler
        self.streamHandler = streamHandler
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await dataHandler(request)
    }

    public func stream(for request: URLRequest) async throws -> AIHTTPStreamResponse {
        try await streamHandler(request)
    }
}
