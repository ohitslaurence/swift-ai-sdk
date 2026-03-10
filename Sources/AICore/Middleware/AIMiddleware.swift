/// A request/response wrapper used to compose provider behavior.
public protocol AIMiddleware: Sendable {
    func transformRequest(_ request: AIRequest) async throws -> AIRequest

    func transformEmbeddingRequest(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingRequest

    func wrapGenerate(
        request: AIRequest,
        next: @Sendable (AIRequest) async throws -> AIResponse
    ) async throws -> AIResponse

    func wrapStream(
        request: AIRequest,
        next: @Sendable (AIRequest) -> AIStream
    ) -> AIStream

    func wrapEmbed(
        request: AIEmbeddingRequest,
        next: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    ) async throws -> AIEmbeddingResponse
}

extension AIMiddleware {
    public func transformRequest(_ request: AIRequest) async throws -> AIRequest {
        request
    }

    public func transformEmbeddingRequest(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingRequest {
        request
    }

    public func wrapGenerate(
        request: AIRequest,
        next: @Sendable (AIRequest) async throws -> AIResponse
    ) async throws -> AIResponse {
        try await next(request)
    }

    public func wrapStream(
        request: AIRequest,
        next: @Sendable (AIRequest) -> AIStream
    ) -> AIStream {
        next(request)
    }

    public func wrapEmbed(
        request: AIEmbeddingRequest,
        next: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    ) async throws -> AIEmbeddingResponse {
        try await next(request)
    }
}
