import Foundation

/// Core engine for the tool execution loop.
///
/// Handles: send request -> extract tool calls -> execute tools (concurrently) ->
/// append assistant + tool result messages -> record AIToolStep -> evaluate stop
/// conditions -> loop or return.
enum AIToolExecution {
    typealias ToolEventHandler = @Sendable (AIToolUse) async throws -> Void
    typealias ToolResultHandler = @Sendable (AIToolResult) async throws -> Void

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
        var totalUsage = AIUsageAccumulator()

        while true {
            try Task.checkCancellation()

            let disableRetryAfterTools = !steps.isEmpty
            if disableRetryAfterTools {
                currentRequest.retryPolicy = .none
            }

            let response = try await provider.complete(currentRequest)

            totalUsage.add(response.usage)

            guard response.finishReason == .toolUse else {
                return AIToolResponse(
                    response: response,
                    steps: steps,
                    totalUsage: totalUsage.value ?? AIUsage(inputTokens: 0, outputTokens: 0),
                    stopReason: .modelStopped
                )
            }

            let toolCalls = extractToolCalls(from: response)
            guard !toolCalls.isEmpty else {
                return AIToolResponse(
                    response: response,
                    steps: steps,
                    totalUsage: totalUsage.value ?? AIUsage(inputTokens: 0, outputTokens: 0),
                    stopReason: .modelStopped
                )
            }

            let toolResults = try await executeTools(
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
                    totalUsage: totalUsage.value ?? AIUsage(inputTokens: 0, outputTokens: 0),
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
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?,
        onToolApprovalRequired: ToolEventHandler? = nil,
        onToolExecuting: ToolEventHandler? = nil,
        onToolResult: ToolResultHandler? = nil
    ) async throws -> [AIToolResult] {
        let toolMap = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        return try await withThrowingTaskGroup(
            of: (Int, AIToolResult).self,
            returning: [AIToolResult].self
        ) { group in
            for (index, toolCall) in toolCalls.enumerated() {
                group.addTask {
                    let result = try await executeSingleTool(
                        toolCall: toolCall,
                        tool: toolMap[toolCall.name],
                        approvalHandler: approvalHandler,
                        toolCallRepairHandler: toolCallRepairHandler,
                        onToolApprovalRequired: onToolApprovalRequired,
                        onToolExecuting: onToolExecuting
                    )

                    if let onToolResult {
                        try await onToolResult(result)
                    }
                    return (index, result)
                }
            }

            var results = [(Int, AIToolResult)]()
            do {
                for try await pair in group {
                    results.append(pair)
                }
            } catch {
                group.cancelAll()
                throw error
            }

            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Execute a single tool call with approval and repair flows.
    private static func executeSingleTool(
        toolCall: AIToolUse,
        tool: AITool?,
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)?,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?,
        onToolApprovalRequired: ToolEventHandler?,
        onToolExecuting: ToolEventHandler?
    ) async throws -> AIToolResult {
        guard let tool else {
            return AIToolResult(
                toolUseId: toolCall.id,
                content: "Unknown tool: \(toolCall.name)",
                isError: true
            )
        }

        if tool.needsApproval {
            if let onToolApprovalRequired {
                try await onToolApprovalRequired(toolCall)
            }

            guard let approvalHandler else {
                return AIToolResult(
                    toolUseId: toolCall.id,
                    content: "Tool execution denied by user",
                    isError: true
                )
            }

            try Task.checkCancellation()
            let approved = await approvalHandler(toolCall)
            try Task.checkCancellation()

            guard approved else {
                return AIToolResult(
                    toolUseId: toolCall.id,
                    content: "Tool execution denied by user",
                    isError: true
                )
            }
        }

        if let onToolExecuting {
            try await onToolExecuting(toolCall)
        }

        do {
            let output = try await tool.handler(toolCall.input)
            try Task.checkCancellation()
            return AIToolResult(toolUseId: toolCall.id, content: output)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as AIToolInputDecodingError {
            return try await executeWithRepair(
                toolCall: toolCall,
                tool: tool,
                errorContext: error.context,
                toolCallRepairHandler: toolCallRepairHandler
            )
        } catch let error as AIError {
            if error == .cancelled {
                throw error
            }

            return makeErrorResult(toolCall: toolCall, context: error.context)
        } catch {
            return makeErrorResult(toolCall: toolCall, context: AIErrorContext(error))
        }
    }

    private static func executeWithRepair(
        toolCall: AIToolUse,
        tool: AITool,
        errorContext: AIErrorContext,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?
    ) async throws -> AIToolResult {
        guard let toolCallRepairHandler else {
            return makeErrorResult(toolCall: toolCall, context: errorContext)
        }

        let repairedData = await toolCallRepairHandler(toolCall, errorContext)
        try Task.checkCancellation()

        guard let repairedData else {
            return makeErrorResult(toolCall: toolCall, context: errorContext)
        }

        do {
            let output = try await tool.handler(repairedData)
            try Task.checkCancellation()
            return AIToolResult(toolUseId: toolCall.id, content: output)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as AIToolInputDecodingError {
            return makeErrorResult(toolCall: toolCall, context: error.context)
        } catch let error as AIError {
            if error == .cancelled {
                throw error
            }

            return makeErrorResult(toolCall: toolCall, context: error.context)
        } catch {
            return makeErrorResult(toolCall: toolCall, context: AIErrorContext(error))
        }
    }

    private static func makeErrorResult(toolCall: AIToolUse, context: AIErrorContext) -> AIToolResult {
        AIToolResult(
            toolUseId: toolCall.id,
            content: context.message,
            isError: true
        )
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
