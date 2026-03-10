import Foundation

/// A provider-neutral response.
public struct AIResponse: Sendable, Codable, Hashable {
    public let id: String
    public let content: [AIContent]
    public let model: String
    public let usage: AIUsage
    public let finishReason: AIFinishReason
    public let warnings: [AIProviderWarning]

    public init(
        id: String,
        content: [AIContent],
        model: String,
        usage: AIUsage = AIUsage(inputTokens: 0, outputTokens: 0),
        finishReason: AIFinishReason = .stop,
        warnings: [AIProviderWarning] = []
    ) {
        self.id = id
        self.content = content
        self.model = model
        self.usage = usage
        self.finishReason = finishReason
        self.warnings = warnings
    }

    public var text: String {
        content.compactMap {
            if case .text(let value) = $0 {
                return value
            }
            return nil
        }.joined()
    }
}

/// Token accounting for a response.
public struct AIUsage: Sendable, Codable, Hashable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// A surfaced provider warning.
public struct AIProviderWarning: Sendable, Codable, Hashable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// The reason a response stopped.
public enum AIFinishReason: String, Sendable, Codable, Hashable {
    case stop
    case maxTokens
    case unknown
}
