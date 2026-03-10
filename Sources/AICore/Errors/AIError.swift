import Foundation

/// Context captured from an underlying error.
public struct AIErrorContext: Error, Sendable, Equatable {
    public let message: String
    public let underlyingType: String?

    public init(message: String, underlyingType: String? = nil) {
        self.message = message
        self.underlyingType = underlyingType
    }

    init(_ error: any Error) {
        self.init(
            message: String(describing: error),
            underlyingType: String(reflecting: type(of: error))
        )
    }
}

/// Common SDK error cases.
public enum AIError: Error, Sendable, Equatable {
    case invalidRequest(String)
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case modelNotFound(String)
    case contentFiltered
    case serverError(statusCode: Int, message: String)
    case networkError(AIErrorContext)
    case decodingError(AIErrorContext)
    case streamInterrupted
    case timeout(AITimeoutKind)
    case unsupportedFeature(String)
    case cancelled
    case maxRetriesExceeded(attempts: Int, lastError: AIErrorContext)
    case noContentGenerated
    case unknown(AIErrorContext)
}

/// The timeout scope that triggered an error.
public enum AITimeoutKind: Sendable, Equatable {
    case total
    case step
    case chunk
}

extension AIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message), .unsupportedFeature(let message):
            return message
        case .authenticationFailed:
            return "Authentication with the AI provider failed."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "The AI provider rate limited the request. Retry after \(retryAfter) seconds."
            }

            return "The AI provider rate limited the request."
        case .modelNotFound(let model):
            return "The requested model was not found: \(model)."
        case .contentFiltered:
            return "The provider filtered the generated content."
        case .serverError(let statusCode, let message):
            return "The AI provider returned server error \(statusCode): \(message)"
        case .networkError(let context):
            return context.message
        case .decodingError(let context):
            return context.message
        case .streamInterrupted:
            return "The stream ended before a terminal finish event was received."
        case .timeout(let kind):
            return "The operation exceeded the configured \(kindDescription(kind)) timeout."
        case .cancelled:
            return "The operation was cancelled."
        case .maxRetriesExceeded(let attempts, let lastError):
            return "The operation failed after \(attempts) attempt(s). Last error: \(lastError.message)"
        case .noContentGenerated:
            return "The provider did not generate any content."
        case .unknown(let context):
            return context.message
        }
    }

    private func kindDescription(_ kind: AITimeoutKind) -> String {
        switch kind {
        case .total:
            return "total"
        case .step:
            return "step"
        case .chunk:
            return "chunk"
        }
    }
}

extension AIError {
    var context: AIErrorContext {
        switch self {
        case .invalidRequest(let message):
            return AIErrorContext(message: message)
        case .authenticationFailed:
            return AIErrorContext(message: "Authentication with the AI provider failed.")
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return AIErrorContext(message: "Rate limited. Retry after \(retryAfter) seconds.")
            }

            return AIErrorContext(message: "Rate limited.")
        case .modelNotFound(let model):
            return AIErrorContext(message: "Model not found: \(model)")
        case .contentFiltered:
            return AIErrorContext(message: "The provider filtered the content.")
        case .serverError(let statusCode, let message):
            return AIErrorContext(message: "Server error \(statusCode): \(message)")
        case .networkError(let context), .decodingError(let context), .unknown(let context):
            return context
        case .streamInterrupted:
            return AIErrorContext(message: "The stream was interrupted before finishing.")
        case .timeout(let kind):
            return AIErrorContext(message: "Timed out waiting for \(kind).")
        case .cancelled:
            return AIErrorContext(message: "The operation was cancelled.")
        case .maxRetriesExceeded(let attempts, let lastError):
            return AIErrorContext(message: "The operation failed after \(attempts) attempt(s): \(lastError.message)")
        case .noContentGenerated:
            return AIErrorContext(message: "The provider did not generate any content.")
        case .unsupportedFeature(let message):
            return AIErrorContext(message: message)
        }
    }
}
