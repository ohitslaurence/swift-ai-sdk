import Foundation

/// A provider-neutral request.
public struct AIRequest: Sendable, Codable, Hashable {
    public var model: AIModel
    public var messages: [AIMessage]
    public var systemPrompt: String?
    public var maxTokens: Int?
    public var temperature: Double?
    public var metadata: [String: String]

    public init(
        model: AIModel,
        messages: [AIMessage],
        systemPrompt: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.metadata = metadata
    }
}

/// Retry settings for provider calls.
public struct RetryPolicy: Sendable, Codable, Hashable {
    public var maxRetries: Int

    public static let `default` = RetryPolicy(maxRetries: 2)

    public init(maxRetries: Int) {
        self.maxRetries = maxRetries
    }
}

/// Timeout settings for provider calls.
public struct AITimeout: Sendable, Codable, Hashable {
    public var total: TimeInterval?

    public static let `default` = AITimeout(total: nil)

    public init(total: TimeInterval?) {
        self.total = total
    }
}
