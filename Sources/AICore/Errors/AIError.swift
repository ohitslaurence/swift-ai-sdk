import Foundation

/// Common SDK error cases.
public enum AIError: Error, Sendable, Equatable {
    case invalidRequest(String)
    case unsupportedFeature(String)
    case cancelled
    case unknown(String)
}

extension AIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message), .unsupportedFeature(let message), .unknown(let message):
            return message
        case .cancelled:
            return "The operation was cancelled."
        }
    }
}
