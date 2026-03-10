import Foundation

extension AIProvider {

    /// Run the tool execution loop until the model stops or a stop condition is met.
    public func completeWithTools(
        _ request: AIRequest,
        stopWhen: [StopCondition] = [.maxSteps(5)],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)? = nil,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)? = nil,
        onStepComplete: (@Sendable (AIToolStep) async -> Void)? = nil
    ) async throws -> AIToolResponse {
        try await AIToolExecution.run(
            provider: self,
            request: request,
            stopConditions: stopWhen,
            approvalHandler: approvalHandler,
            toolCallRepairHandler: toolCallRepairHandler,
            onStepComplete: onStepComplete
        )
    }

    /// Run the streaming tool execution loop, returning a stitched stream of events.
    public func streamWithTools(
        _ request: AIRequest,
        stopWhen: [StopCondition] = [.maxSteps(5)],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)? = nil,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)? = nil,
        onStepComplete: (@Sendable (AIToolStep) async -> Void)? = nil
    ) -> AIToolStream {
        AIToolStream.create(
            provider: self,
            request: request,
            stopConditions: stopWhen,
            approvalHandler: approvalHandler,
            toolCallRepairHandler: toolCallRepairHandler,
            onStepComplete: onStepComplete
        )
    }
}
