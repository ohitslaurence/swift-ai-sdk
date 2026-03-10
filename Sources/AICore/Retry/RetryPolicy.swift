import Foundation

/// Retry configuration for provider requests.
public struct RetryPolicy: Sendable, Codable, Equatable {
    public var maxRetries: Int
    public var initialDelay: TimeInterval
    public var backoffMultiplier: Double
    public var maxDelay: TimeInterval

    public static let `default` = RetryPolicy(
        maxRetries: 2,
        initialDelay: 2.0,
        backoffMultiplier: 2.0,
        maxDelay: 60.0
    )

    public static let none = RetryPolicy(
        maxRetries: 0,
        initialDelay: 0,
        backoffMultiplier: 1,
        maxDelay: 0
    )

    public init(maxRetries: Int, initialDelay: TimeInterval, backoffMultiplier: Double, maxDelay: TimeInterval) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.backoffMultiplier = backoffMultiplier
        self.maxDelay = maxDelay
    }
}
