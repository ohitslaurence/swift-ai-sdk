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

    /// Split text into chunks according to the given mode.
    /// Returns an array where the last element is the incomplete remainder (possibly empty).
    static func split(_ text: String, mode: ChunkMode) -> [String] {
        switch mode {
        case .character:
            return text.map(String.init) + [""]
        case .word:
            return splitByBoundary(text, separator: " ")
        case .line:
            return splitByBoundary(text, separator: "\n")
        }
    }

    private static func splitByBoundary(_ text: String, separator: Character) -> [String] {
        var chunks: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if char == separator {
                chunks.append(current)
                current = ""
            }
        }
        chunks.append(current)
        return chunks
    }
}
