import Foundation

/// A single-pass async sequence of stream events.
///
/// Internally this wraps `AsyncThrowingStream<..., any Error>` instead of an
/// `AIError`-typed stream because current Swift concurrency constraints make the
/// stricter typed form impractical for the SDK's stream wrappers. Public helper
/// behavior still normalizes surfaced failures to `AIError` values.
public struct AIStream: AsyncSequence, Sendable {
    public typealias Element = AIStreamEvent
    public typealias AsyncIterator = AsyncThrowingStream<AIStreamEvent, any Error>.Iterator

    private let stream: AsyncThrowingStream<AIStreamEvent, any Error>
    private let warningProvider: @Sendable () async -> [AIProviderWarning]

    public init(_ stream: AsyncThrowingStream<AIStreamEvent, any Error>) {
        self.init(wrapping: stream, applyLifecyclePolicy: true, warningProvider: { [] })
    }

    package init(
        _ stream: AsyncThrowingStream<AIStreamEvent, any Error>,
        warnings: [AIProviderWarning]
    ) {
        self.init(wrapping: stream, applyLifecyclePolicy: true, warningProvider: { warnings })
    }

    init(
        wrapping stream: AsyncThrowingStream<AIStreamEvent, any Error>,
        applyLifecyclePolicy: Bool,
        warningProvider: @escaping @Sendable () async -> [AIProviderWarning]
    ) {
        self.stream = applyLifecyclePolicy ? Self.makeLifecycleStream(from: stream) : stream
        self.warningProvider = warningProvider
    }

    public func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }

    public func collect() async throws -> AIResponse {
        var identifier = UUID().uuidString
        var model = "unknown"
        var usage = AIUsage(inputTokens: 0, outputTokens: 0)
        var finishReason: AIFinishReason?
        var sawEvent = false
        var content: [CollectedContent] = []
        var toolIndexes: [String: Int] = [:]

        for try await event in self {
            sawEvent = true

            switch event {
            case .start(let id, let startedModel):
                identifier = id
                model = startedModel
            case .delta(.text(let delta)):
                if case .text(let existing) = content.last {
                    content[content.count - 1] = .text(existing + delta)
                } else {
                    content.append(.text(delta))
                }
            case .delta(.toolInput(let id, let jsonDelta)):
                guard let toolIndex = toolIndexes[id] else {
                    continue
                }

                content[toolIndex].appendToolInput(jsonDelta)
            case .toolUseStart(let id, let name):
                toolIndexes[id] = content.count
                content.append(.toolUse(id: id, name: name, jsonInput: ""))
            case .usage(let updatedUsage):
                usage = updatedUsage
            case .finish(let reason):
                finishReason = reason
            }
        }

        guard let finishReason else {
            if sawEvent {
                throw AIError.streamInterrupted
            }

            throw AIError.noContentGenerated
        }

        return AIResponse(
            id: identifier,
            content: content.map { $0.contentValue },
            model: model,
            usage: usage,
            finishReason: finishReason,
            warnings: await responseWarnings()
        )
    }

    public var textStream: AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream<String, any Error>(String.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await event in self {
                        if case .delta(.text(let text)) = event {
                            continuation.yield(text)
                        }
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
    }

    public var accumulatedText: AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream<String, any Error>(String.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                var accumulated = ""

                do {
                    for try await chunk in textStream {
                        accumulated += chunk
                        continuation.yield(accumulated)
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
    }

    public func smooth(_ config: SmoothStreaming = .default) -> AIStream {
        let source = self
        let stream = AsyncThrowingStream<AIStreamEvent, any Error>(
            AIStreamEvent.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            let task = Task {
                var buffer = ""

                func flushBuffer() {
                    guard !buffer.isEmpty else { return }
                    continuation.yield(.delta(.text(buffer)))
                    buffer = ""
                }

                func emitChunks(_ text: String) async {
                    buffer += text
                    let chunks = SmoothStreaming.split(buffer, mode: config.mode)
                    guard chunks.count > 1 else { return }
                    for chunk in chunks.dropLast() {
                        continuation.yield(.delta(.text(chunk)))
                        do {
                            try await Task.sleep(
                                nanoseconds: UInt64(config.delay * 1_000_000_000)
                            )
                        } catch {
                            flushBuffer()
                            return
                        }
                    }
                    buffer = chunks.last ?? ""
                }

                do {
                    for try await event in source {
                        switch event {
                        case .delta(.text(let text)):
                            await emitChunks(text)
                        case .finish:
                            flushBuffer()
                            continuation.yield(event)
                        default:
                            continuation.yield(event)
                        }
                    }
                    flushBuffer()
                    continuation.finish()
                } catch is CancellationError {
                    flushBuffer()
                    continuation.finish(throwing: AIError.cancelled)
                } catch let error as AIError {
                    flushBuffer()
                    continuation.finish(throwing: error)
                } catch {
                    flushBuffer()
                    continuation.finish(throwing: AIError.unknown(AIErrorContext(error)))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return AIStream(
            wrapping: stream,
            applyLifecyclePolicy: false,
            warningProvider: warningProvider
        )
    }

    public static func finished(text: String = "", model: String = "mock") -> AIStream {
        AIStream(
            AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
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
            AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
                continuation.finish(throwing: error)
            }
        )
    }

    private static func makeLifecycleStream(
        from source: AsyncThrowingStream<AIStreamEvent, any Error>
    ) -> AsyncThrowingStream<AIStreamEvent, any Error> {
        AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
            continuation in
            let task = Task {
                var sawEvent = false
                var sawFinish = false

                do {
                    for try await event in source {
                        sawEvent = true

                        if case .finish = event {
                            sawFinish = true
                        }

                        continuation.yield(event)
                    }

                    if sawEvent, !sawFinish {
                        continuation.finish(throwing: AIError.streamInterrupted)
                    } else {
                        continuation.finish()
                    }
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
    }

    func responseWarnings() async -> [AIProviderWarning] {
        await warningProvider()
    }
}

actor AIStreamWarningStore {
    private var warnings: [AIProviderWarning] = []

    func set(_ warnings: [AIProviderWarning]) {
        self.warnings = warnings
    }

    func get() -> [AIProviderWarning] {
        warnings
    }
}

private enum CollectedContent {
    case text(String)
    case toolUse(id: String, name: String, jsonInput: String)

    mutating func appendToolInput(_ delta: String) {
        guard case .toolUse(let id, let name, let jsonInput) = self else {
            return
        }

        self = .toolUse(id: id, name: name, jsonInput: jsonInput + delta)
    }

    var contentValue: AIContent {
        switch self {
        case .text(let value):
            return .text(value)
        case .toolUse(let id, let name, let jsonInput):
            return .toolUse(
                AIToolUse(
                    id: id,
                    name: name,
                    input: Data(jsonInput.utf8)
                )
            )
        }
    }
}
