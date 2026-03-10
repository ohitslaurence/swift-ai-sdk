/// Middleware that fills in missing generation defaults.
public struct DefaultSettingsMiddleware: AIMiddleware, Sendable {
    public var maxTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var toolChoice: AIToolChoice?
    public var allowParallelToolCalls: Bool?
    public var responseFormat: AIResponseFormat?

    public init(
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        toolChoice: AIToolChoice? = nil,
        allowParallelToolCalls: Bool? = nil,
        responseFormat: AIResponseFormat? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.toolChoice = toolChoice
        self.allowParallelToolCalls = allowParallelToolCalls
        self.responseFormat = responseFormat
    }

    public func transformRequest(_ request: AIRequest) async throws -> AIRequest {
        var request = request

        if request.maxTokens == nil {
            request.maxTokens = maxTokens
        }

        if request.temperature == nil {
            request.temperature = temperature
        }

        if request.topP == nil {
            request.topP = topP
        }

        if request.toolChoice == nil {
            request.toolChoice = toolChoice
        }

        if request.allowParallelToolCalls == nil {
            request.allowParallelToolCalls = allowParallelToolCalls
        }

        if request.responseFormat == .text, let responseFormat {
            request.responseFormat = responseFormat
        }

        return request
    }
}
