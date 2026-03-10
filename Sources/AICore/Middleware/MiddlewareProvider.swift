import Foundation

struct MiddlewareProvider: AIProvider, Sendable {
    let provider: any AIProvider
    let middlewares: [any AIMiddleware]

    var availableModels: [AIModel] {
        provider.availableModels
    }

    var capabilities: AIProviderCapabilities {
        provider.capabilities
    }

    func complete(_ request: AIRequest) async throws -> AIResponse {
        let transformedRequest = try await transformedRequest(from: request)
        let operation = wrappedGenerateOperation()
        return try await operation(transformedRequest)
    }

    func stream(_ request: AIRequest) -> AIStream {
        AIStream(
            AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
                let task = Task {
                    do {
                        let transformedRequest = try await transformedRequest(from: request)
                        let stream = wrappedStreamOperation()(transformedRequest)

                        for try await event in stream {
                            continuation.yield(event)
                        }

                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: AIError.cancelled)
                    } catch let error as AIError {
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(throwing: AIError.unknown(AIErrorContext(error)))
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        )
    }

    func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        let transformedRequest = try await transformedEmbeddingRequest(from: request)
        let operation = wrappedEmbedOperation()
        return try await operation(transformedRequest)
    }

    private func transformedRequest(from request: AIRequest) async throws -> AIRequest {
        var request = request
        for middleware in middlewares {
            request = try await middleware.transformRequest(request)
        }
        return request
    }

    private func transformedEmbeddingRequest(from request: AIEmbeddingRequest) async throws -> AIEmbeddingRequest {
        var request = request
        for middleware in middlewares {
            request = try await middleware.transformEmbeddingRequest(request)
        }
        return request
    }

    private func wrappedGenerateOperation() -> @Sendable (AIRequest) async throws -> AIResponse {
        var next: @Sendable (AIRequest) async throws -> AIResponse = { request in
            try await provider.complete(request)
        }

        for middleware in middlewares.reversed() {
            let currentNext = next
            next = { request in
                try await middleware.wrapGenerate(request: request, next: currentNext)
            }
        }

        return next
    }

    private func wrappedStreamOperation() -> @Sendable (AIRequest) -> AIStream {
        var next: @Sendable (AIRequest) -> AIStream = { request in
            provider.stream(request)
        }

        for middleware in middlewares.reversed() {
            let currentNext = next
            next = { request in
                middleware.wrapStream(request: request, next: currentNext)
            }
        }

        return next
    }

    private func wrappedEmbedOperation() -> @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        var next: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse = { request in
            try await provider.embed(request)
        }

        for middleware in middlewares.reversed() {
            let currentNext = next
            next = { request in
                try await middleware.wrapEmbed(request: request, next: currentNext)
            }
        }

        return next
    }
}

/// Wraps a provider with middleware applied in array order.
public func withMiddleware(
    _ provider: any AIProvider,
    middleware: [any AIMiddleware]
) -> any AIProvider {
    MiddlewareProvider(provider: provider, middlewares: middleware)
}
