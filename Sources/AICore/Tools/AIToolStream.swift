import Foundation

/// A stitched async sequence of tool stream events across multiple steps.
///
/// Uses `AsyncThrowingStream<..., any Error>` internally (same pattern as `AIStream` —
/// see AGENTS.md settled decisions).
public struct AIToolStream: AsyncSequence, Sendable {
    public typealias Element = AIToolStreamEvent
    public typealias AsyncIterator = AsyncThrowingStream<AIToolStreamEvent, any Error>.Iterator

    private let stream: AsyncThrowingStream<AIToolStreamEvent, any Error>

    public init(_ stream: AsyncThrowingStream<AIToolStreamEvent, any Error>) {
        self.stream = stream
    }

    public func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }
}

/// Events emitted by the streaming tool execution loop.
public enum AIToolStreamEvent: Sendable {
    case streamEvent(AIStreamEvent)
    case toolApprovalRequired(AIToolUse)
    case toolExecuting(AIToolUse)
    case toolResult(AIToolResult)
    case stepComplete(AIToolStep)
}

extension AIToolStream {

    /// Create a streaming tool execution loop.
    static func create(
        provider: any AIProvider,
        request: AIRequest,
        stopConditions: [StopCondition],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)?,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?,
        onStepComplete: (@Sendable (AIToolStep) async -> Void)?
    ) -> AIToolStream {
        let stream = AsyncThrowingStream<AIToolStreamEvent, any Error>(
            AIToolStreamEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        ) { continuation in
            let task = Task {
                await streamLoop(
                    continuation: continuation,
                    provider: provider,
                    request: request,
                    stopConditions: stopConditions,
                    approvalHandler: approvalHandler,
                    toolCallRepairHandler: toolCallRepairHandler,
                    onStepComplete: onStepComplete
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return AIToolStream(stream)
    }

    private static func streamLoop(
        continuation: AsyncThrowingStream<AIToolStreamEvent, any Error>.Continuation,
        provider: any AIProvider,
        request: AIRequest,
        stopConditions: [StopCondition],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)?,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?,
        onStepComplete: (@Sendable (AIToolStep) async -> Void)?
    ) async {
        var currentRequest = request
        var steps: [AIToolStep] = []

        while true {
            if Task.isCancelled {
                continuation.finish(throwing: AIError.cancelled)
                return
            }

            let disableRetryAfterTools = !steps.isEmpty
            if disableRetryAfterTools {
                currentRequest.retryPolicy = .none
            }

            let providerStream = provider.stream(currentRequest)
            var sawEvent = false
            var response: AIResponse

            do {
                var content: [CollectedStreamContent] = []
                var toolIndexes: [String: Int] = [:]
                var identifier = UUID().uuidString
                var model = "unknown"
                var usage = AIUsage(inputTokens: 0, outputTokens: 0)
                var finishReason: AIFinishReason?

                for try await event in providerStream {
                    sawEvent = true
                    continuation.yield(.streamEvent(event))

                    switch event {
                    case .start(let id, let startedModel):
                        identifier = id
                        model = startedModel
                    case .delta(.text(let delta)):
                        if case .text(let existing) = content.last {
                            content[content.count - 1] = .text(existing + delta)
                        } else {
                            content.append(.text(delta))
                        }
                    case .delta(.toolInput(let id, let jsonDelta)):
                        guard let toolIndex = toolIndexes[id] else { continue }
                        content[toolIndex].appendToolInput(jsonDelta)
                    case .toolUseStart(let id, let name):
                        toolIndexes[id] = content.count
                        content.append(.toolUse(id: id, name: name, jsonInput: ""))
                    case .usage(let updatedUsage):
                        usage = updatedUsage
                    case .finish(let reason):
                        finishReason = reason
                    }
                }

                guard let finishReason else {
                    if sawEvent {
                        continuation.finish(throwing: AIError.streamInterrupted)
                    } else {
                        continuation.finish(throwing: AIError.noContentGenerated)
                    }
                    return
                }

                response = AIResponse(
                    id: identifier,
                    content: content.map(\.contentValue),
                    model: model,
                    usage: usage,
                    finishReason: finishReason
                )
            } catch is CancellationError {
                continuation.finish(throwing: AIError.cancelled)
                return
            } catch let error as AIError {
                if sawEvent {
                    continuation.finish(throwing: AIError.streamInterrupted)
                } else {
                    continuation.finish(throwing: error)
                }
                return
            } catch {
                if sawEvent {
                    continuation.finish(throwing: AIError.streamInterrupted)
                } else {
                    continuation.finish(throwing: AIError.unknown(AIErrorContext(error)))
                }
                return
            }

            guard response.finishReason == .toolUse else {
                continuation.finish()
                return
            }

            let toolCalls = AIToolExecution.extractToolCalls(from: response)
            guard !toolCalls.isEmpty else {
                continuation.finish()
                return
            }

            let toolResults = await executeToolsStreaming(
                toolCalls: toolCalls,
                tools: currentRequest.tools,
                approvalHandler: approvalHandler,
                toolCallRepairHandler: toolCallRepairHandler,
                continuation: continuation
            )

            let appendedMessages = AIToolExecution.buildTranscriptMessages(
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

            continuation.yield(.stepComplete(step))
            await onStepComplete?(step)

            if let matched = await AIToolExecution.evaluateStopConditions(stopConditions, steps: steps) {
                _ = matched
                continuation.finish()
                return
            }

            currentRequest.messages.append(contentsOf: appendedMessages)
        }
    }

    /// Execute tools in streaming mode, emitting events for each tool.
    private static func executeToolsStreaming(
        toolCalls: [AIToolUse],
        tools: [AITool],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)?,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?,
        continuation: AsyncThrowingStream<AIToolStreamEvent, any Error>.Continuation
    ) async -> [AIToolResult] {
        let toolMap = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        let unorderedResults = await withTaskGroup(
            of: (Int, AIToolResult).self,
            returning: [AIToolResult].self
        ) { group in
            for (index, toolCall) in toolCalls.enumerated() {
                group.addTask {
                    let tool = toolMap[toolCall.name]

                    if let tool, tool.needsApproval {
                        continuation.yield(.toolApprovalRequired(toolCall))
                    }

                    let result = await executeSingleToolStreaming(
                        toolCall: toolCall,
                        tool: tool,
                        approvalHandler: approvalHandler,
                        toolCallRepairHandler: toolCallRepairHandler,
                        continuation: continuation
                    )
                    continuation.yield(.toolResult(result))
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

    private static func executeSingleToolStreaming(
        toolCall: AIToolUse,
        tool: AITool?,
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)?,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)?,
        continuation: AsyncThrowingStream<AIToolStreamEvent, any Error>.Continuation
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

            if Task.isCancelled {
                return AIToolResult(toolUseId: toolCall.id, content: "Cancelled", isError: true)
            }

            let approved = await approvalHandler(toolCall)

            if Task.isCancelled {
                return AIToolResult(toolUseId: toolCall.id, content: "Cancelled", isError: true)
            }

            guard approved else {
                return AIToolResult(
                    toolUseId: toolCall.id,
                    content: "Tool execution denied by user",
                    isError: true
                )
            }
        }

        continuation.yield(.toolExecuting(toolCall))

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
}

/// Content accumulator for stream collection (mirrors AIStream's internal pattern).
private enum CollectedStreamContent {
    case text(String)
    case toolUse(id: String, name: String, jsonInput: String)

    mutating func appendToolInput(_ delta: String) {
        guard case .toolUse(let id, let name, let jsonInput) = self else { return }
        self = .toolUse(id: id, name: name, jsonInput: jsonInput + delta)
    }

    var contentValue: AIContent {
        switch self {
        case .text(let value):
            return .text(value)
        case .toolUse(let id, let name, let jsonInput):
            return .toolUse(AIToolUse(id: id, name: name, input: Data(jsonInput.utf8)))
        }
    }
}
