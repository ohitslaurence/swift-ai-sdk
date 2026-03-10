import Foundation

package enum RetryExecutor {
    package static func execute<T>(
        policy: RetryPolicy,
        operation: @escaping @Sendable (_ attempt: Int) async throws -> T
    ) async throws -> T {
        var attempt = 0

        while true {
            try Task.checkCancellation()
            attempt += 1

            do {
                return try await operation(attempt)
            } catch is CancellationError {
                throw AIError.cancelled
            } catch let error as AIError {
                guard isRetryable(error), policy.maxRetries > 0 else {
                    throw error
                }

                if shouldRetry(error: error, policy: policy, attempt: attempt) {
                    let delay = delay(forAttempt: attempt, policy: policy, retryAfter: retryAfter(from: error))
                    try await AITimeoutController.sleep(seconds: delay)
                    continue
                }

                throw AIError.maxRetriesExceeded(attempts: attempt, lastError: error.context)
            } catch {
                throw AIError.unknown(AIErrorContext(error))
            }
        }
    }

    package static func executeStream(
        policy: RetryPolicy,
        timeout: AITimeout,
        operation: @escaping @Sendable (_ attempt: Int) async throws -> AIStream
    ) -> AIStream {
        let warningStore = AIStreamWarningStore()

        return AIStream(
            wrapping: AsyncThrowingStream<AIStreamEvent, any Error>(
                AIStreamEvent.self,
                bufferingPolicy: .unbounded
            ) { continuation in
                let task = Task {
                    do {
                        try await AITimeoutController.withTimeout(timeout.total, kind: .total) {
                            var attempt = 0

                            while true {
                                try Task.checkCancellation()
                                attempt += 1
                                let currentAttempt = attempt
                                var hasReceivedStreamEvent = false

                                do {
                                    let stream = try await AITimeoutController.withTimeout(timeout.step, kind: .step) {
                                        try await operation(currentAttempt)
                                    }
                                    await warningStore.set(await stream.responseWarnings())

                                    let timedStream = AITimeoutController.enforceChunkTimeout(
                                        on: stream,
                                        timeout: timeout.chunk
                                    )

                                    for try await event in timedStream {
                                        hasReceivedStreamEvent = true
                                        continuation.yield(event)
                                    }

                                    return
                                } catch is CancellationError {
                                    throw AIError.cancelled
                                } catch let error as AIError {
                                    if shouldRetry(
                                        error: error,
                                        policy: policy,
                                        attempt: currentAttempt,
                                        hasReceivedStreamEvent: hasReceivedStreamEvent
                                    ) {
                                        let retryDelay = delay(
                                            forAttempt: currentAttempt,
                                            policy: policy,
                                            retryAfter: retryAfter(from: error)
                                        )
                                        try await AITimeoutController.sleep(seconds: retryDelay)
                                        continue
                                    }

                                    if isRetryable(error), !hasReceivedStreamEvent, policy.maxRetries > 0,
                                        currentAttempt > policy.maxRetries
                                    {
                                        throw AIError.maxRetriesExceeded(
                                            attempts: currentAttempt,
                                            lastError: error.context
                                        )
                                    }

                                    throw error
                                }
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
            },
            applyLifecyclePolicy: false,
            warningProvider: { await warningStore.get() }
        )
    }

    package static func shouldRetry(
        error: AIError,
        policy: RetryPolicy,
        attempt: Int,
        hasReceivedStreamEvent: Bool = false,
        hasExecutedTool: Bool = false
    ) -> Bool {
        guard !hasReceivedStreamEvent, !hasExecutedTool else {
            return false
        }

        guard isRetryable(error) else {
            return false
        }

        return attempt <= policy.maxRetries
    }

    package static func delay(
        forAttempt attempt: Int,
        policy: RetryPolicy,
        retryAfter: TimeInterval?
    ) -> TimeInterval {
        let exponent = Double(max(0, attempt - 1))
        let exponentialDelay = min(
            policy.maxDelay,
            policy.initialDelay * pow(policy.backoffMultiplier, exponent)
        )

        guard let retryAfter, retryAfter >= 0, retryAfter <= policy.maxDelay else {
            return exponentialDelay
        }

        return max(exponentialDelay, retryAfter)
    }

    package static func isRetryable(_ error: AIError) -> Bool {
        switch error {
        case .rateLimited:
            return true
        case .serverError(let statusCode, _):
            return statusCode == 408 || statusCode == 409 || statusCode >= 500
        default:
            return false
        }
    }

    private static func retryAfter(from error: AIError) -> TimeInterval? {
        guard case .rateLimited(let retryAfter) = error else {
            return nil
        }

        return retryAfter
    }
}
