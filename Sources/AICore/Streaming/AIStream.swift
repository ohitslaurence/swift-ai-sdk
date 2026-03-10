import Foundation

/// A single-pass async sequence of stream events.
public struct AIStream: AsyncSequence, Sendable {
    public typealias Element = AIStreamEvent
    public typealias AsyncIterator = AsyncThrowingStream<AIStreamEvent, any Error>.Iterator

    private let stream: AsyncThrowingStream<AIStreamEvent, any Error>

    public init(_ stream: AsyncThrowingStream<AIStreamEvent, any Error>) {
        self.stream = stream
    }

    public func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }

    public func collect() async throws -> AIResponse {
        var identifier = UUID().uuidString
        var model = "unknown"
        var text = ""
        var usage = AIUsage(inputTokens: 0, outputTokens: 0)
        var finishReason = AIFinishReason.stop

        for try await event in self {
            switch event {
            case .start(let id, let startedModel):
                identifier = id
                model = startedModel
            case .delta(.text(let delta)):
                text += delta
            case .usage(let updatedUsage):
                usage = updatedUsage
            case .finish(let reason):
                finishReason = reason
            }
        }

        return AIResponse(
            id: identifier,
            content: [.text(text)],
            model: model,
            usage: usage,
            finishReason: finishReason
        )
    }

    public var textStream: AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in self {
                        if case .delta(.text(let text)) = event {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIError.unknown(String(describing: error)))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public var accumulatedText: AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var accumulated = ""

                do {
                    for try await chunk in textStream {
                        accumulated += chunk
                        continuation.yield(accumulated)
                    }
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIError.unknown(String(describing: error)))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func smooth(_ config: SmoothStreaming = .default) -> AIStream {
        _ = config
        return self
    }

    public static func finished(text: String = "", model: String = "mock") -> AIStream {
        AIStream(
            AsyncThrowingStream { continuation in
                continuation.yield(.start(id: UUID().uuidString, model: model))
                if !text.isEmpty {
                    continuation.yield(.delta(.text(text)))
                }
                continuation.yield(.finish(.stop))
                continuation.finish()
            }
        )
    }

    public static func failed(_ error: AIError) -> AIStream {
        AIStream(
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        )
    }
}

/// A streamed event.
public enum AIStreamEvent: Sendable {
    case start(id: String, model: String)
    case delta(AIStreamDelta)
    case usage(AIUsage)
    case finish(AIFinishReason)
}

/// A streamed delta.
public enum AIStreamDelta: Sendable {
    case text(String)
}

/// Smooth streaming configuration.
public struct SmoothStreaming: Sendable {
    public enum ChunkMode: Sendable {
        case word
        case line
        case character
    }

    public var delay: TimeInterval
    public var mode: ChunkMode

    public static let `default` = SmoothStreaming(delay: 0.01, mode: .word)

    public init(delay: TimeInterval, mode: ChunkMode) {
        self.delay = delay
        self.mode = mode
    }
}
