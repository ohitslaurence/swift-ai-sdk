import Foundation

/// Timeout configuration for provider requests.
public struct AITimeout: Sendable, Codable, Equatable {
    public var total: TimeInterval?
    public var step: TimeInterval?
    public var chunk: TimeInterval?

    public static let `default` = AITimeout(total: nil, step: nil, chunk: nil)

    public init(total: TimeInterval? = nil, step: TimeInterval? = nil, chunk: TimeInterval? = nil) {
        self.total = total
        self.step = step
        self.chunk = chunk
    }
}

package enum AITimeoutController {
    package static func withTimeout<T: Sendable>(
        _ timeout: TimeInterval?,
        kind: AITimeoutKind,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()

        guard let timeout, timeout > 0 else {
            do {
                return try await operation()
            } catch is CancellationError {
                throw AIError.cancelled
            }
        }

        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    do {
                        return try await operation()
                    } catch is CancellationError {
                        throw AIError.cancelled
                    }
                }

                group.addTask {
                    try await sleep(seconds: timeout)
                    throw AIError.timeout(kind)
                }

                guard let result = try await group.next() else {
                    throw AIError.timeout(kind)
                }

                group.cancelAll()
                return result
            }
        } catch is CancellationError {
            throw AIError.cancelled
        }
    }

    package static func enforceChunkTimeout(on stream: AIStream, timeout: TimeInterval?) -> AIStream {
        guard let timeout, timeout > 0 else {
            return stream
        }

        return AIStream(
            wrapping: AsyncThrowingStream<AIStreamEvent, any Error>(
                AIStreamEvent.self,
                bufferingPolicy: .unbounded
            ) { continuation in
                let state = ChunkTimeoutState()
                let consumerTask = Task {
                    await state.noteActivity()

                    do {
                        for try await event in stream {
                            await state.noteActivity()
                            continuation.yield(event)
                        }

                        await state.finish()
                        continuation.finish()
                    } catch is CancellationError {
                        await state.finish()
                        continuation.finish(throwing: AIError.cancelled)
                    } catch let error as AIError {
                        await state.finish()
                        continuation.finish(throwing: error)
                    } catch {
                        await state.finish()
                        continuation.finish(throwing: AIError.unknown(AIErrorContext(error)))
                    }
                }
                let watchdogTask = Task {
                    do {
                        while true {
                            try await sleep(seconds: timeout)

                            switch await state.status(after: timeout) {
                            case .active:
                                continue
                            case .finished:
                                return
                            case .timedOut:
                                consumerTask.cancel()
                                continuation.finish(throwing: AIError.timeout(.chunk))
                                return
                            }
                        }
                    } catch is AIError {
                        return
                    } catch {
                        return
                    }
                }

                continuation.onTermination = { _ in
                    consumerTask.cancel()
                    watchdogTask.cancel()
                }
            },
            applyLifecyclePolicy: false,
            warningProvider: { await stream.responseWarnings() }
        )
    }

    package static func sleep(seconds: TimeInterval) async throws {
        let clampedSeconds = max(0, seconds)
        let nanoseconds = UInt64(clampedSeconds * 1_000_000_000)

        do {
            try await Task.sleep(nanoseconds: nanoseconds)
        } catch is CancellationError {
            throw AIError.cancelled
        }
    }
}

private actor ChunkTimeoutState {
    private var isFinished = false
    private var lastActivity = Date()

    func noteActivity() {
        lastActivity = Date()
    }

    func finish() {
        isFinished = true
    }

    func status(after timeout: TimeInterval) -> ChunkTimeoutStatus {
        if isFinished {
            return .finished
        }

        if Date().timeIntervalSince(lastActivity) >= timeout {
            return .timedOut
        }

        return .active
    }
}

private enum ChunkTimeoutStatus {
    case active
    case finished
    case timedOut
}
