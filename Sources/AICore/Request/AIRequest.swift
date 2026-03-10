import Foundation

/// A single request to an AI provider.
public struct AIRequest: Sendable {
    public var model: AIModel
    public var messages: [AIMessage]
    public var systemPrompt: String?
    public var tools: [AITool]
    public var toolChoice: AIToolChoice?
    public var allowParallelToolCalls: Bool?
    public var responseFormat: AIResponseFormat
    public var maxTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var stopSequences: [String]
    public var metadata: [String: String]
    public var retryPolicy: RetryPolicy
    public var timeout: AITimeout
    public var headers: [String: String]

    public init(
        model: AIModel,
        messages: [AIMessage],
        systemPrompt: String? = nil,
        tools: [AITool] = [],
        toolChoice: AIToolChoice? = nil,
        allowParallelToolCalls: Bool? = nil,
        responseFormat: AIResponseFormat = .text,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stopSequences: [String] = [],
        metadata: [String: String] = [:],
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default,
        headers: [String: String] = [:]
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.toolChoice = toolChoice
        self.allowParallelToolCalls = allowParallelToolCalls
        self.responseFormat = responseFormat
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.metadata = metadata
        self.retryPolicy = retryPolicy
        self.timeout = timeout
        self.headers = headers
    }
}
