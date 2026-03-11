@testable import AICore

/// Records provider calls for tests.
public actor MockProviderRecorder {
    public private(set) var completeCalls: [AIRequest] = []
    public private(set) var streamCalls: [AIRequest] = []
    public private(set) var embedCalls: [AIEmbeddingRequest] = []

    public init() {}

    public func recordComplete(_ request: AIRequest) {
        completeCalls.append(request)
    }

    public func recordStream(_ request: AIRequest) {
        streamCalls.append(request)
    }

    public func recordEmbed(_ request: AIEmbeddingRequest) {
        embedCalls.append(request)
    }
}

/// A configurable mock provider.
public struct MockProvider: AIProvider, Sendable {
    public var completionHandler: @Sendable (AIRequest) async throws -> AIResponse
    public var streamHandler: @Sendable (AIRequest) -> AIStream
    public var embeddingHandler: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    public var availableModels: [AIModel]
    public var capabilities: AIProviderCapabilities
    public let recorder: MockProviderRecorder

    public init(
        completionHandler: @escaping @Sendable (AIRequest) async throws -> AIResponse = { request in
            AIResponse(id: "mock", content: request.messages.first?.content ?? [], model: request.model.id)
        },
        streamHandler: @escaping @Sendable (AIRequest) -> AIStream = { _ in
            .finished(text: "mock")
        },
        embeddingHandler: @escaping @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse = { request in
            let embeddings = request.inputs.enumerated().map { index, _ in
                AIEmbedding(index: index, vector: [0.0, 1.0])
            }
            return AIEmbeddingResponse(model: request.model.id, embeddings: embeddings)
        },
        availableModels: [AIModel] = [],
        capabilities: AIProviderCapabilities = .default,
        recorder: MockProviderRecorder = MockProviderRecorder()
    ) {
        self.completionHandler = completionHandler
        self.streamHandler = streamHandler
        self.embeddingHandler = embeddingHandler
        self.availableModels = availableModels
        self.capabilities = capabilities
        self.recorder = recorder
    }

    public func complete(_ request: AIRequest) async throws -> AIResponse {
        await recorder.recordComplete(request)
        return try await completionHandler(request)
    }

    public func stream(_ request: AIRequest) -> AIStream {
        let stream = streamHandler(request)
        let warningStore = AIStreamWarningStore()

        return AIStream(
            wrapping: AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
                let task = Task {
                    await recorder.recordStream(request)

                    do {
                        await warningStore.set(await stream.responseWarnings())

                        for try await event in stream {
                            continuation.yield(event)
                        }

                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: AIError.cancelled)
                    } catch let error as AIError {
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(
                            throwing: AIError.unknown(
                                AIErrorContext(
                                    message: String(describing: error),
                                    underlyingType: String(reflecting: type(of: error))
                                )
                            )
                        )
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            },
            applyLifecyclePolicy: true,
            warningProvider: { await warningStore.get() }
        )
    }

    public func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        await recorder.recordEmbed(request)
        return try await embeddingHandler(request)
    }
}
