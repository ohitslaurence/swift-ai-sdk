import Foundation

/// A reusable wrapper over the tool execution loop.
///
/// Encapsulates a provider, model, system prompt, tools, and stop conditions
/// into a single callable agent.
public struct Agent: Sendable {
    public let provider: any AIProvider
    public let model: AIModel
    public let systemPrompt: String?
    public let tools: [AITool]
    public let stopConditions: [StopCondition]
    public var approvalHandler: (@Sendable (AIToolUse) async -> Bool)?
    public var toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?
    public var onStepComplete: (@Sendable (AIToolStep) async -> Void)?

    public init(
        provider: any AIProvider,
        model: AIModel,
        systemPrompt: String? = nil,
        tools: [AITool] = [],
        stopConditions: [StopCondition] = [.maxSteps(10)],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)? = nil,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)? = nil,
        onStepComplete: (@Sendable (AIToolStep) async -> Void)? = nil
    ) {
        self.provider = provider
        self.model = model
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.stopConditions = stopConditions
        self.approvalHandler = approvalHandler
        self.toolCallRepairHandler = toolCallRepairHandler
        self.onStepComplete = onStepComplete
    }

    /// Run the agent with a single user message.
    public func run(_ message: String) async throws -> AIToolResponse {
        try await run(messages: [.user(message)])
    }

    /// Run the agent with a streaming tool loop.
    public func stream(_ message: String) -> AIToolStream {
        let request = AIRequest(
            model: model,
            messages: [.user(message)],
            systemPrompt: systemPrompt,
            tools: tools
        )

        return provider.streamWithTools(
            request,
            stopWhen: stopConditions,
            approvalHandler: approvalHandler,
            toolCallRepairHandler: toolCallRepairHandler,
            onStepComplete: onStepComplete
        )
    }

    /// Run the agent with a full conversation history.
    public func run(messages: [AIMessage]) async throws -> AIToolResponse {
        let request = AIRequest(
            model: model,
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools
        )

        return try await provider.completeWithTools(
            request,
            stopWhen: stopConditions,
            approvalHandler: approvalHandler,
            toolCallRepairHandler: toolCallRepairHandler,
            onStepComplete: onStepComplete
        )
    }
}
