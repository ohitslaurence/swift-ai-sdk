import Foundation
import XCTest

@testable import AICore

final class RetryAndTimeoutTests: XCTestCase {
    func test_retryPolicyDefaultsMatchSpec() {
        XCTAssertEqual(
            RetryPolicy.default, RetryPolicy(maxRetries: 2, initialDelay: 2, backoffMultiplier: 2, maxDelay: 60))
        XCTAssertEqual(RetryPolicy.none, RetryPolicy(maxRetries: 0, initialDelay: 0, backoffMultiplier: 1, maxDelay: 0))
    }

    func test_retryExecutorDelay_usesMaximumOfServerDelayAndExponentialDelay() {
        let policy = RetryPolicy(maxRetries: 2, initialDelay: 2, backoffMultiplier: 2, maxDelay: 60)

        XCTAssertEqual(RetryExecutor.delay(forAttempt: 1, policy: policy, retryAfter: 1), 2)
        XCTAssertEqual(RetryExecutor.delay(forAttempt: 2, policy: policy, retryAfter: 10), 10)
        XCTAssertEqual(RetryExecutor.delay(forAttempt: 2, policy: policy, retryAfter: 120), 4)
    }

    func test_retryExecutor_onlyRetriesRetryableErrors() {
        let policy = RetryPolicy.default
        let networkError = AIError.networkError(AIErrorContext(message: "offline"))

        XCTAssertTrue(RetryExecutor.shouldRetry(error: .rateLimited(retryAfter: nil), policy: policy, attempt: 1))
        XCTAssertTrue(
            RetryExecutor.shouldRetry(
                error: .serverError(statusCode: 408, message: "timeout"), policy: policy, attempt: 1))
        XCTAssertTrue(
            RetryExecutor.shouldRetry(
                error: .serverError(statusCode: 409, message: "conflict"), policy: policy, attempt: 1))
        XCTAssertTrue(
            RetryExecutor.shouldRetry(error: .serverError(statusCode: 500, message: "boom"), policy: policy, attempt: 1)
        )
        XCTAssertFalse(
            RetryExecutor.shouldRetry(
                error: .serverError(statusCode: 404, message: "missing"), policy: policy, attempt: 1))
        XCTAssertFalse(RetryExecutor.shouldRetry(error: networkError, policy: policy, attempt: 1))
        XCTAssertFalse(
            RetryExecutor.shouldRetry(
                error: .rateLimited(retryAfter: nil),
                policy: policy,
                attempt: 1,
                hasReceivedStreamEvent: true
            )
        )
        XCTAssertFalse(
            RetryExecutor.shouldRetry(
                error: .rateLimited(retryAfter: nil),
                policy: policy,
                attempt: 1,
                hasExecutedTool: true
            )
        )
    }

    func test_retryExecutor_retriesRetryableErrorsUntilSuccess() async throws {
        let policy = RetryPolicy(maxRetries: 2, initialDelay: 0, backoffMultiplier: 1, maxDelay: 0)
        let recorder = AttemptRecorder()

        let value = try await RetryExecutor.execute(policy: policy) { attempt in
            await recorder.set(attempt)

            if attempt < 3 {
                throw AIError.rateLimited(retryAfter: nil)
            }

            return "ok"
        }

        XCTAssertEqual(value, "ok")
        let attempts = await recorder.value
        XCTAssertEqual(attempts, 3)
    }

    func test_retryExecutor_whenCancelledDuringBackoff_throwsCancelled() async {
        let task = Task {
            try await RetryExecutor.execute(
                policy: RetryPolicy(maxRetries: 2, initialDelay: 1, backoffMultiplier: 1, maxDelay: 1)
            ) { _ in
                throw AIError.rateLimited(retryAfter: nil)
            }
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as AIError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_timeoutController_timesOutLongOperation() async {
        do {
            _ = try await AITimeoutController.withTimeout(0.05, kind: .total) {
                try await Task.sleep(nanoseconds: 200_000_000)
                return 1
            }
            XCTFail("Expected timeout")
        } catch let error as AIError {
            XCTAssertEqual(error, .timeout(.total))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_timeoutController_chunkTimeoutFailsStalledStream() async {
        let stream = AIStream(
            AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
                let task = Task {
                    continuation.yield(.start(id: "stream_1", model: "claude-sonnet-4-5"))

                    do {
                        try await Task.sleep(nanoseconds: 200_000_000)
                        continuation.yield(.finish(.stop))
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: AIError.cancelled)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        )
        let timedStream = AITimeoutController.enforceChunkTimeout(on: stream, timeout: 0.05)

        do {
            _ = try await timedStream.collect()
            XCTFail("Expected chunk timeout")
        } catch let error as AIError {
            XCTAssertEqual(error, .timeout(.chunk))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_retryExecutorExecuteStream_retriesRetryableFailureBeforeFirstEvent() async throws {
        let policy = RetryPolicy(maxRetries: 2, initialDelay: 0, backoffMultiplier: 1, maxDelay: 0)
        let recorder = AttemptRecorder()

        let stream = RetryExecutor.executeStream(policy: policy, timeout: .default) { attempt in
            await recorder.set(attempt)

            if attempt == 1 {
                return .failed(.rateLimited(retryAfter: nil))
            }

            return .finished(text: "ok", model: "gpt-4o")
        }

        let response = try await stream.collect()
        let attempts = await recorder.value

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(attempts, 2)
    }

    func test_retryExecutorExecuteStream_doesNotRetryAfterFirstEvent() async {
        let policy = RetryPolicy(maxRetries: 2, initialDelay: 0, backoffMultiplier: 1, maxDelay: 0)
        let recorder = AttemptRecorder()
        let stream = RetryExecutor.executeStream(policy: policy, timeout: .default) { attempt in
            await recorder.set(attempt)

            return AIStream(
                AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                    continuation in
                    continuation.yield(.start(id: "stream_\(attempt)", model: "gpt-4o"))
                    continuation.yield(.delta(.text("partial")))
                    continuation.finish(throwing: AIError.rateLimited(retryAfter: nil))
                }
            )
        }

        do {
            _ = try await stream.collect()
            XCTFail("Expected the stream to fail")
        } catch let error as AIError {
            let attempts = await recorder.value
            XCTAssertEqual(error, .rateLimited(retryAfter: nil))
            XCTAssertEqual(attempts, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor AttemptRecorder {
    private(set) var value = 0

    func set(_ value: Int) {
        self.value = value
    }
}
