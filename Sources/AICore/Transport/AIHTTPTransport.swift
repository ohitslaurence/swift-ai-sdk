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
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.networkError(
                    AIErrorContext(message: "Received a non-HTTP response from the transport")
                )
            }

            return (data, httpResponse)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.networkError(AIErrorContext(error))
        }
    }

    public func stream(for request: URLRequest) async throws -> AIHTTPStreamResponse {
        try Task.checkCancellation()

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.networkError(
                    AIErrorContext(message: "Received a non-HTTP streaming response from the transport")
                )
            }

            let body = AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) { continuation in
                let task = Task {
                    var buffer = Data()
                    buffer.reserveCapacity(1_024)

                    do {
                        for try await byte in bytes {
                            buffer.append(byte)

                            if buffer.count >= 1_024 {
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }

                        if !buffer.isEmpty {
                            continuation.yield(buffer)
                        }

                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: AIError.cancelled)
                    } catch let error as AIError {
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(throwing: AIError.networkError(AIErrorContext(error)))
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }

            return AIHTTPStreamResponse(response: httpResponse, body: body)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.networkError(AIErrorContext(error))
        }
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
