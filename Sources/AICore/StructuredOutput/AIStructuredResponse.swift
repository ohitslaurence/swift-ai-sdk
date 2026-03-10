/// A structured output response wrapping a decoded value and the underlying AI response.
public struct AIStructuredResponse<T: Sendable>: Sendable {
    /// The decoded value.
    public let value: T

    /// The raw AI response from the provider.
    public let response: AIResponse

    /// The number of attempts made (1 = first try succeeded).
    public let attempts: Int

    public init(value: T, response: AIResponse, attempts: Int) {
        self.value = value
        self.response = response
        self.attempts = attempts
    }

    /// Token usage from the underlying response.
    public var usage: AIUsage { response.usage }

    /// Provider warnings from the underlying response.
    public var warnings: [AIProviderWarning] { response.warnings }
}
