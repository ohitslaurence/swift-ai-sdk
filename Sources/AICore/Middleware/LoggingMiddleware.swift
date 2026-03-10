import Foundation

/// Middleware that logs generation, streaming, and embedding activity.
public struct LoggingMiddleware: AIMiddleware, Sendable {
    public typealias Logger = @Sendable (String) -> Void

    private let logger: Logger

    public init(logger: @escaping Logger = { _ in }) {
        self.logger = logger
    }

    public func wrapGenerate(
        request: AIRequest,
        next: @Sendable (AIRequest) async throws -> AIResponse
    ) async throws -> AIResponse {
        let clock = ContinuousClock()
        let start = clock.now
        logger("[AI] complete start model=\(request.model.id)")

        do {
            let response = try await next(request)
            let duration = clock.now - start
            logWarnings(response.warnings, prefix: "complete")
            logger("[AI] complete finish model=\(response.model) duration=\(duration)")
            return response
        } catch {
            let duration = clock.now - start
            logger("[AI] complete error duration=\(duration) error=\(error)")
            throw error
        }
    }

    public func wrapStream(
        request: AIRequest,
        next: @Sendable (AIRequest) -> AIStream
    ) -> AIStream {
        let upstream = next(request)
        logger("[AI] stream start model=\(request.model.id)")

        return AIStream(
            wrapping: AsyncThrowingStream<AIStreamEvent, any Error>(
                AIStreamEvent.self,
                bufferingPolicy: .unbounded
            ) {
                continuation in
                let task = Task {
                    do {
                        for try await event in upstream {
                            logger("[AI] stream event=\(String(describing: event))")
                            continuation.yield(event)
                        }

                        logger("[AI] stream finish model=\(request.model.id)")
                        continuation.finish()
                    } catch is CancellationError {
                        logger("[AI] stream cancelled model=\(request.model.id)")
                        continuation.finish(throwing: AIError.cancelled)
                    } catch let error as AIError {
                        logger("[AI] stream error=\(error)")
                        continuation.finish(throwing: error)
                    } catch {
                        let mappedError = AIError.unknown(AIErrorContext(error))
                        logger("[AI] stream error=\(mappedError)")
                        continuation.finish(throwing: mappedError)
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            },
            applyLifecyclePolicy: true,
            warningProvider: { await upstream.responseWarnings() }
        )
    }

    public func wrapEmbed(
        request: AIEmbeddingRequest,
        next: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    ) async throws -> AIEmbeddingResponse {
        let clock = ContinuousClock()
        let start = clock.now
        logger("[AI] embed start model=\(request.model.id) inputs=\(request.inputs.count)")

        do {
            let response = try await next(request)
            let duration = clock.now - start
            logWarnings(response.warnings, prefix: "embed")
            logger("[AI] embed finish model=\(response.model) duration=\(duration)")
            return response
        } catch {
            let duration = clock.now - start
            logger("[AI] embed error duration=\(duration) error=\(error)")
            throw error
        }
    }

    private func logWarnings(_ warnings: [AIProviderWarning], prefix: String) {
        for warning in warnings {
            if let parameter = warning.parameter {
                logger(
                    "[AI] \(prefix) warning code=\(warning.code) parameter=\(parameter) message=\(warning.message)"
                )
            } else {
                logger("[AI] \(prefix) warning code=\(warning.code) message=\(warning.message)")
            }
        }
    }
}
