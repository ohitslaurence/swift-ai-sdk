/// A request/response wrapper used to compose provider behavior.
public protocol AIMiddleware: Sendable {
    func transformRequest(_ request: AIRequest) async throws -> AIRequest
    func wrapGenerate(
        request: AIRequest,
        next: @Sendable (AIRequest) async throws -> AIResponse
    ) async throws -> AIResponse
}

extension AIMiddleware {
    public func transformRequest(_ request: AIRequest) async throws -> AIRequest {
        request
    }

    public func wrapGenerate(
        request: AIRequest,
        next: @Sendable (AIRequest) async throws -> AIResponse
    ) async throws -> AIResponse {
        try await next(request)
    }
}

/// A no-op logging middleware scaffold.
public struct LoggingMiddleware: AIMiddleware {
    public init() {}
}

/// A no-op defaults middleware scaffold.
public struct DefaultSettingsMiddleware: AIMiddleware {
    public init() {}
}

/// Wraps a provider with middleware.
public func withMiddleware(
    _ provider: any AIProvider,
    middleware: [any AIMiddleware]
) -> any AIProvider {
    _ = middleware
    return provider
}
