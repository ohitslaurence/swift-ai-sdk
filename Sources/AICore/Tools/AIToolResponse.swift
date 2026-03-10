/// The result of a multi-step tool execution loop.
public struct AIToolResponse: Sendable {
    public let response: AIResponse
    public let steps: [AIToolStep]
    public let totalUsage: AIUsage
    public let stopReason: StopReason

    public init(
        response: AIResponse,
        steps: [AIToolStep],
        totalUsage: AIUsage,
        stopReason: StopReason
    ) {
        self.response = response
        self.steps = steps
        self.totalUsage = totalUsage
        self.stopReason = stopReason
    }
}

/// Why the tool execution loop ended.
public enum StopReason: Sendable, Equatable {
    case modelStopped
    case conditionMet(String)
}

/// A single tool-using step in the execution loop.
public struct AIToolStep: Sendable {
    public let toolCalls: [AIToolUse]
    public let toolResults: [AIToolResult]
    public let usage: AIUsage
    public let response: AIResponse
    public let appendedMessages: [AIMessage]

    public init(
        toolCalls: [AIToolUse],
        toolResults: [AIToolResult],
        usage: AIUsage,
        response: AIResponse,
        appendedMessages: [AIMessage]
    ) {
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.usage = usage
        self.response = response
        self.appendedMessages = appendedMessages
    }
}
