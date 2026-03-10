import Foundation

/// Configuration for smoothing text emitted by an ``AIStream``.
public struct SmoothStreaming: Sendable, Equatable {
    public enum ChunkMode: Sendable, Equatable {
        case word
        case line
        case character
    }

    public var delay: TimeInterval
    public var mode: ChunkMode

    public static let `default` = SmoothStreaming(delay: 0.01, mode: .word)

    public init(delay: TimeInterval = 0.01, mode: ChunkMode = .word) {
        self.delay = delay
        self.mode = mode
    }
}
