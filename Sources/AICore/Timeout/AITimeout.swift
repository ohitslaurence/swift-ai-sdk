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

enum AITimeoutController {
    static func withTimeout<T: Sendable>(
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

    static func enforceChunkTimeout(on stream: AIStream, timeout: TimeInterval?) -> AIStream {
        _ = timeout
        return stream
    }

    static func sleep(seconds: TimeInterval) async throws {
        let clampedSeconds = max(0, seconds)
        let nanoseconds = UInt64(clampedSeconds * 1_000_000_000)

        do {
            try await Task.sleep(nanoseconds: nanoseconds)
        } catch is CancellationError {
            throw AIError.cancelled
        }
    }
}
