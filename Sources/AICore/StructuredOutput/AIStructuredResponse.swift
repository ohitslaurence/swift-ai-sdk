/// A structured output response wrapping a decoded value and the underlying AI response.
public struct AIStructuredResponse<T: Sendable>: Sendable {
    /// The decoded value.
    public let value: T

    /// The raw AI response from the provider.
    public let response: AIResponse

    /// The number of attempts made (1 = first try succeeded).
    public let attempts: Int

    private let totalUsage: AIUsage
    private let accumulatedWarnings: [AIProviderWarning]

    public init(
        value: T,
        response: AIResponse,
        attempts: Int,
        usage: AIUsage? = nil,
        warnings: [AIProviderWarning]? = nil
    ) {
        self.value = value
        self.response = response
        self.attempts = attempts
        self.totalUsage = usage ?? response.usage
        self.accumulatedWarnings = warnings ?? response.warnings
    }

    /// Token usage across the full structured-output operation.
    public var usage: AIUsage { totalUsage }

    /// Provider warnings accumulated across the structured-output operation.
    public var warnings: [AIProviderWarning] { accumulatedWarnings }
}
