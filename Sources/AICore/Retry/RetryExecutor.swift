import Foundation

enum RetryExecutor {
    static func execute<T>(
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

    static func shouldRetry(
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

    static func delay(
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

    static func isRetryable(_ error: AIError) -> Bool {
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
