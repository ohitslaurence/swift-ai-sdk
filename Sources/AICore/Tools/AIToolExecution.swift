import Foundation

/// Core engine for the tool execution loop.
///
/// Handles: send request -> extract tool calls -> execute tools (concurrently) ->
/// append assistant + tool result messages -> record AIToolStep -> evaluate stop
/// conditions -> loop or return.
enum AIToolExecution {

    /// Run the non-streaming tool execution loop.
    static func run(
        provider: any AIProvider,
        request: AIRequest,
        stopConditions: [StopCondition],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)?,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?,
        onStepComplete: (@Sendable (AIToolStep) async -> Void)?
    ) async throws -> AIToolResponse {
        var currentRequest = request
        var steps: [AIToolStep] = []
        var totalInput = 0
        var totalOutput = 0

        while true {
            try Task.checkCancellation()

            let disableRetryAfterTools = !steps.isEmpty
            if disableRetryAfterTools {
                currentRequest.retryPolicy = .none
            }

            let response = try await provider.complete(currentRequest)

            totalInput += response.usage.inputTokens
            totalOutput += response.usage.outputTokens

            guard response.finishReason == .toolUse else {
                return AIToolResponse(
                    response: response,
                    steps: steps,
                    totalUsage: AIUsage(inputTokens: totalInput, outputTokens: totalOutput),
                    stopReason: .modelStopped
                )
            }

            let toolCalls = extractToolCalls(from: response)
            guard !toolCalls.isEmpty else {
                return AIToolResponse(
                    response: response,
                    steps: steps,
                    totalUsage: AIUsage(inputTokens: totalInput, outputTokens: totalOutput),
                    stopReason: .modelStopped
                )
            }

            let toolResults = await executeTools(
                toolCalls: toolCalls,
                tools: currentRequest.tools,
                approvalHandler: approvalHandler,
                toolCallRepairHandler: toolCallRepairHandler
            )

            let appendedMessages = buildTranscriptMessages(
                response: response,
                toolResults: toolResults
            )

            let step = AIToolStep(
                toolCalls: toolCalls,
                toolResults: toolResults,
                usage: response.usage,
                response: response,
                appendedMessages: appendedMessages
            )
            steps.append(step)

            await onStepComplete?(step)

            if let matched = await evaluateStopConditions(stopConditions, steps: steps) {
                return AIToolResponse(
                    response: response,
                    steps: steps,
                    totalUsage: AIUsage(inputTokens: totalInput, outputTokens: totalOutput),
                    stopReason: .conditionMet(matched.description)
                )
            }

            currentRequest.messages.append(contentsOf: appendedMessages)
        }
    }

    /// Execute all tool calls for a single step, concurrently when multiple.
    static func executeTools(
        toolCalls: [AIToolUse],
        tools: [AITool],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)?,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?
    ) async -> [AIToolResult] {
        let toolMap = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        let unorderedResults = await withTaskGroup(
            of: (Int, AIToolResult).self,
            returning: [AIToolResult].self
        ) { group in
            for (index, toolCall) in toolCalls.enumerated() {
                group.addTask {
                    let result = await executeSingleTool(
                        toolCall: toolCall,
                        tool: toolMap[toolCall.name],
                        approvalHandler: approvalHandler,
                        toolCallRepairHandler: toolCallRepairHandler
                    )
                    return (index, result)
                }
            }

            var results = [(Int, AIToolResult)]()
            for await pair in group {
                results.append(pair)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }

        return unorderedResults
    }

    /// Execute a single tool call with approval and repair flows.
    private static func executeSingleTool(
        toolCall: AIToolUse,
        tool: AITool?,
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)?,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?
    ) async -> AIToolResult {
        guard let tool else {
            return AIToolResult(
                toolUseId: toolCall.id,
                content: "Unknown tool: \(toolCall.name)",
                isError: true
            )
        }

        if tool.needsApproval {
            guard let approvalHandler else {
                return AIToolResult(
                    toolUseId: toolCall.id,
                    content: "Tool execution denied by user",
                    isError: true
                )
            }

            if Task.isCancelled { return makeCancelledResult(toolCall) }

            let approved = await approvalHandler(toolCall)

            if Task.isCancelled { return makeCancelledResult(toolCall) }

            guard approved else {
                return AIToolResult(
                    toolUseId: toolCall.id,
                    content: "Tool execution denied by user",
                    isError: true
                )
            }
        }

        do {
            let output = try await tool.handler(toolCall.input)
            return AIToolResult(toolUseId: toolCall.id, content: output)
        } catch {
            if let toolCallRepairHandler {
                let errorContext = AIErrorContext(
                    message: String(describing: error),
                    underlyingType: String(reflecting: type(of: error))
                )

                if let repairedData = await toolCallRepairHandler(toolCall, errorContext) {
                    do {
                        let output = try await tool.handler(repairedData)
                        return AIToolResult(toolUseId: toolCall.id, content: output)
                    } catch {
                        let repairErrorContext = AIErrorContext(
                            message: String(describing: error),
                            underlyingType: String(reflecting: type(of: error))
                        )
                        return AIToolResult(
                            toolUseId: toolCall.id,
                            content: repairErrorContext.message,
                            isError: true
                        )
                    }
                }
            }

            let errorContext = AIErrorContext(
                message: String(describing: error),
                underlyingType: String(reflecting: type(of: error))
            )
            return AIToolResult(
                toolUseId: toolCall.id,
                content: errorContext.message,
                isError: true
            )
        }
    }

    private static func makeCancelledResult(_ toolCall: AIToolUse) -> AIToolResult {
        AIToolResult(toolUseId: toolCall.id, content: "Cancelled", isError: true)
    }

    /// Extract tool call blocks from the response content.
    static func extractToolCalls(from response: AIResponse) -> [AIToolUse] {
        response.content.compactMap { content in
            if case .toolUse(let toolUse) = content {
                return toolUse
            }
            return nil
        }
    }

    /// Build the transcript messages appended after a tool-using step.
    ///
    /// Order: (1) one assistant message with raw content, (2) one tool message per result.
    static func buildTranscriptMessages(
        response: AIResponse,
        toolResults: [AIToolResult]
    ) -> [AIMessage] {
        var messages: [AIMessage] = []
        messages.append(.assistant(response.content))
        for result in toolResults {
            messages.append(
                AIMessage(role: .tool, content: [.toolResult(result)])
            )
        }
        return messages
    }

    /// Evaluate stop conditions with OR logic. Returns the first matched condition.
    static func evaluateStopConditions(
        _ conditions: [StopCondition],
        steps: [AIToolStep]
    ) async -> StopCondition? {
        for condition in conditions {
            if await condition.evaluate(steps) {
                return condition
            }
        }
        return nil
    }
}
