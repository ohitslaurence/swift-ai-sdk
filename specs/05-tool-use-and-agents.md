# Spec 05: Tool Use & Agentic Loops

> Let the model call functions and run multi-step reasoning loops autonomously.

## Goal

Implement the tool execution loop: model calls a tool -> SDK executes it -> sends result back -> model continues. Support both single-step tool use and multi-step agentic loops with configurable limits, approval hooks, cancellation, and streaming.

## Review History

- 2026-03-11: Deep implementation audit completed against `AICore`, provider transcript mapping, `Agent`, `AISwiftUI` integration assumptions, docs, and regression coverage. The audit corrected cancellation commit behavior, restricted tool-call repair to typed decode failures, preserved streamed warning/error fidelity, tightened stitched-stream buffering semantics, and expanded regression coverage.

## Dependencies

- Spec 01 (AICore)
- Spec 04 for typed input schema generation via `AIStructured`

## Public API

### Typed Tool Definition

```swift
extension AITool {
    /// Convenience: create a tool with typed Codable input and Encodable output.
    public static func define<Input: AIStructured, Output: Encodable & Sendable>(
        name: String,
        description: String,
        needsApproval: Bool = false,
        handler: @escaping @Sendable (Input) async throws -> Output
    ) throws -> AITool
}
```

Notes:

- The helper derives `inputSchema` from `Input.jsonSchema`.
- `Output` is JSON-encoded when it is not already a `String`.
- The stored `AITool.handler` remains `Data -> String` so provider-independent execution stays simple.

### Automatic Tool Execution

```swift
extension AIProvider {
    public func completeWithTools(
        _ request: AIRequest,
        stopWhen: [StopCondition] = [.maxSteps(5)],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)? = nil,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)? = nil,
        onStepComplete: (@Sendable (AIToolStep) async -> Void)? = nil
    ) async throws -> AIToolResponse

    public func streamWithTools(
        _ request: AIRequest,
        stopWhen: [StopCondition] = [.maxSteps(5)],
        approvalHandler: (@Sendable (AIToolUse) async -> Bool)? = nil,
        toolCallRepairHandler: (@Sendable (AIToolUse, AIErrorContext) async -> Data?)? = nil,
        onStepComplete: (@Sendable (AIToolStep) async -> Void)? = nil
    ) -> AIToolStream
}

public struct AIToolResponse: Sendable {
    public let response: AIResponse
    public let steps: [AIToolStep]
    public let totalUsage: AIUsage
    public let stopReason: StopReason
}

public enum StopReason: Sendable {
    case modelStopped
    case conditionMet(String)
}

public struct AIToolStep: Sendable {
    public let toolCalls: [AIToolUse]
    public let toolResults: [AIToolResult]
    public let usage: AIUsage
    public let response: AIResponse
    public let appendedMessages: [AIMessage]
}

public struct AIToolStream: AsyncSequence, Sendable {
    public typealias Element = AIToolStreamEvent
    public typealias AsyncIterator = AsyncThrowingStream<AIToolStreamEvent, any Error>.Iterator

    public init(_ stream: AsyncThrowingStream<AIToolStreamEvent, any Error>)
    public func makeAsyncIterator() -> AsyncIterator
}

public enum AIToolStreamEvent: Sendable {
    case streamEvent(AIStreamEvent)
    case toolApprovalRequired(AIToolUse)
    case toolExecuting(AIToolUse)
    case toolResult(AIToolResult)
    case stepComplete(AIToolStep)
}

public struct StopCondition: Sendable {
    public let description: String
    public let evaluate: @Sendable ([AIToolStep]) async -> Bool

    public static func maxSteps(_ n: Int) -> StopCondition
    public static func toolCalled(_ name: String) -> StopCondition
    public static func custom(
        description: String,
        _ predicate: @escaping @Sendable ([AIToolStep]) async -> Bool
    ) -> StopCondition
}
```

### Agent

```swift
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
    )

    public func run(_ message: String) async throws -> AIToolResponse
    public func stream(_ message: String) -> AIToolStream
    public func run(messages: [AIMessage]) async throws -> AIToolResponse
}
```

### Usage

```swift
struct WeatherInput: AIStructured {
    let city: String
}

let weatherTool = try AITool.define(
    name: "get_weather",
    description: "Get current weather for a city"
) { (input: WeatherInput) async throws -> String in
    let weather = try await weatherAPI.get(city: input.city)
    return "Temperature: \(weather.temp)F, Conditions: \(weather.conditions)"
}

let response = try await provider.completeWithTools(
    AIRequest(
        model: .claude(.sonnet4_5),
        messages: [.user("What's the weather in London and Paris?")],
        tools: [weatherTool]
    )
)

let assistant = Agent(
    provider: provider,
    model: .claude(.sonnet4_5),
    systemPrompt: "You are a helpful weather assistant.",
    tools: [weatherTool],
    stopConditions: [.maxSteps(5)]
)
```

## Implementation Details

### Tool Execution Loop

```
1. Send the request to the provider.
2. If finishReason == .toolUse:
   a. Extract tool calls from the assistant response.
   b. Execute tools.
   c. Append the assistant message + tool result messages to the transcript.
   d. Record an AIToolStep.
   e. Evaluate stop conditions.
   f. If no condition matched, send the next request.
3. If finishReason != .toolUse:
   return final response + step history with stopReason = .modelStopped.
```

Important semantic rule:

- `.maxSteps(n)` is a normal `StopCondition`. Hitting it returns `AIToolResponse(stopReason: .conditionMet(...))`. It is not an error and there is no separate `AIError.maxStepsExceeded` path.

### Exact Transcript Replay

After each tool-using step, `AICore` appends messages in this exact order:

1. One `.assistant(...)` message containing the raw assistant content from the provider response, including `AIContent.toolUse` blocks.
2. One `.tool(...)` message per `AIToolResult`, in the same order as the model's tool calls.

`AIToolStep.appendedMessages` stores these messages verbatim.

Provider modules are responsible only for mapping this provider-neutral transcript into their wire format.

### Parallel Tool Execution

When the model returns multiple tool calls in one step, execute them concurrently.

Use a non-throwing `TaskGroup` and convert failures into `AIToolResult(isError: true)` inside each child task:

```swift
await withTaskGroup(of: (AIToolUse, AIToolResult).self) { group in
    for toolCall in toolCalls {
        group.addTask {
            do {
                let result = try await executeTool(toolCall)
                return (toolCall, result)
            } catch {
                let context = AIErrorContext(message: String(describing: error), underlyingType: String(reflecting: type(of: error)))
                return (toolCall, AIToolResult(toolUseId: toolCall.id, content: context.message, isError: true))
            }
        }
    }
}
```

### Tool Approval

Approval applies to both `completeWithTools` / `streamWithTools` and `Agent`.

Rules:

1. If `needsApproval == false`, execute immediately.
2. If `needsApproval == true` and no `approvalHandler` exists, treat the tool as denied.
3. If denied, synthesize `AIToolResult(toolUseId:, content: "Tool execution denied by user", isError: true)`.
4. In streaming mode, emit `.toolApprovalRequired` before waiting for approval.
5. If cancellation is observed while waiting for approval, stop immediately without synthesizing a denial result.

### Tool Call Repair

When a typed tool call's JSON input cannot be decoded:

1. Create an `AIErrorContext` describing the parse failure.
2. Invoke `toolCallRepairHandler` if present.
3. If it returns repaired `Data`, retry the decode once.
4. If repair still fails, send an error tool result back to the model.

This avoids spending a full extra LLM round-trip on trivial JSON mistakes.

### Tool Errors

If a tool handler throws:

- catch the error
- convert it into `AIToolResult(isError: true)`
- continue the loop

Tool failures are part of the transcript, not fatal loop errors.

### Stop Conditions

- Default for `completeWithTools` / `streamWithTools`: `[.maxSteps(5)]`
- Default for `Agent`: `[.maxSteps(10)]`
- Conditions use OR logic: the first matched condition stops the loop.
- When a condition matches, return the latest `AIToolResponse` with `.conditionMet(description)`.

### Cancellation & Retry Semantics

- Task cancellation must cancel:
  - the active provider request
  - any pending retry backoff sleep
  - all in-flight tool tasks
- Cancellation while awaiting approval must stop the loop immediately without producing synthetic tool results.
- No automatic retry is allowed after any tool has executed, even if the next provider request fails.
- Streaming tool loops must surface cancellation immediately and stop yielding outer events.

### Streaming Tool Execution (Stitchable Stream)

Multi-step streaming uses a stitched outer `AsyncThrowingStream` with bounded buffering:

1. Start the first provider stream and forward raw `AIStreamEvent`s as `.streamEvent`.
2. When the stream finishes with `.toolUse`, execute approval + tools.
3. Emit `.toolExecuting`, `.toolResult`, and `.stepComplete` events.
4. Start the next provider stream and continue forwarding events through the same outer sequence.
5. End only when the model stops naturally, a stop condition triggers, or an error/cancellation occurs.

Backpressure rule:

- The outer stream must keep buffering bounded without silently dropping stitched events. If the buffer is full, the producer side must back off rather than lose transcript or tool lifecycle events.

### Stream Interruption Recovery

- If the active provider stream fails after emitting any `AIStreamEvent`, surface `AIError.streamInterrupted` unless a more specific `AIError` is available and should be preserved.
- Do not automatically restart the interrupted tool-loop step, even if previous completed steps had no side effects.
- Only completed `AIToolStep`s remain committed. Partial assistant text from the interrupted in-flight step stays transient and is not appended to the transcript.

## File Layout

```
Sources/AICore/
├── Tools/
│   ├── AITool.swift
│   ├── AIToolExecution.swift
│   ├── AIToolResponse.swift
│   ├── AIToolStream.swift
│   └── StopCondition.swift
└── Agent/
    └── Agent.swift
```

## Tests

1. Single tool call executes and returns a final model response.
2. Multiple tool calls in one step execute concurrently.
3. Multi-step loop calls tools across multiple turns.
4. `.maxSteps` returns `.conditionMet`, not an error.
5. `.toolCalled` stop condition stops the loop.
6. Custom stop condition stops the loop.
7. Multiple stop conditions use OR logic.
8. Tool handler failures are returned to the model as error results.
9. Approval-gated tools execute when approved.
10. Approval-gated tools are denied when no approval handler exists.
11. Approval-gated tools return denial results when rejected.
12. Tool call repair succeeds with repaired JSON input.
13. Tool call repair falls back to an error result when repair fails.
14. `AITool.define` derives schema from `Input.jsonSchema`.
15. `AITool.define` JSON-encodes non-string outputs.
16. `Agent.run()` works end to end.
17. `Agent.run(messages:)` preserves conversation history.
18. `streamWithTools` emits a seamless stitched stream across steps.
19. `streamWithTools` emits `.toolApprovalRequired` before approval-gated execution.
20. Cancellation stops the active provider request and in-flight tools.
21. No automatic retry occurs after a tool side effect.
22. `onStepComplete` fires once per completed step.
23. `AIToolStep.appendedMessages` matches the documented transcript replay order.
24. Interrupted stitched streams surface `AIError.streamInterrupted` and preserve only previously completed steps.
25. Cancellation while waiting for approval stops without synthesizing a denial tool result.
26. Specific streamed `AIError` values are preserved after partial output when available.
27. Cancellation during tool execution does not commit a partial completed step.
28. Cancellation during approval does not commit a partial completed step.
29. Tool call repair is attempted only for typed decode failures, not arbitrary tool handler errors.
30. Streamed provider warnings are preserved on `AIToolStep.response`.
31. `AIToolResponse.totalUsage` preserves token detail accounting across all completed responses.
32. Slow consumers do not silently drop stitched stream events.

## Acceptance Criteria

- [ ] `completeWithTools` and `streamWithTools` both accept approval + repair hooks.
- [ ] `StopCondition.maxSteps` is a normal stop condition, not an exception path.
- [ ] Transcript replay after each tool step is specified exactly and tested.
- [ ] Multiple tool calls in one response execute concurrently.
- [ ] Tool errors are surfaced as tool results, not fatal loop errors.
- [ ] Cancellation propagates through provider requests, retries, and tool tasks.
- [ ] Interrupted stitched streams surface an error and do not auto-restart the active step.
- [ ] No automatic retry occurs after any tool executes.
- [ ] `Agent` is a reusable wrapper over the same lower-level loop semantics.
- [ ] Streaming tool execution uses a single stitched outer stream with bounded buffering.
- [ ] `AITool.define` supports typed input plus structured encodable output.
- [ ] All 32 test cases pass.
