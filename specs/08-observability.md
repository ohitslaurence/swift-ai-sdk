# Spec 08: Observability & Telemetry

> Visibility without pollution. Observe requests, streams, tools, retries, and cost surfaces without turning middleware into a grab bag.

## Goal

Define a structured observability surface for `AICore` that covers request/response lifecycle events, streaming events, tool-loop events, embedding events, metrics, and accounting exposure.

The design must complement middleware rather than replace it:

- middleware transforms or wraps behavior
- telemetry observes immutable, redacted snapshots
- logging can be built from telemetry, but telemetry must remain machine-readable

## Dependencies

- Spec 01 (requests, streams, retry, middleware, embeddings)
- Spec 05 (tool loops and stitched streams)
- Spec 07 (embedding batching and aggregation)

## Public API

```swift
public protocol AITelemetrySink: Sendable {
    func record(_ event: AITelemetryEvent) async
}

public struct AITelemetryConfiguration: Sendable {
    public var sinks: [any AITelemetrySink]
    public var redaction: AITelemetryRedaction
    public var includeMetrics: Bool
    public var includeUsage: Bool
    public var includeAccounting: Bool

    public static let `default`: AITelemetryConfiguration

    public init(
        sinks: [any AITelemetrySink],
        redaction: AITelemetryRedaction = .default,
        includeMetrics: Bool = true,
        includeUsage: Bool = true,
        includeAccounting: Bool = true
    )
}

public enum AITelemetryCaptureMode: Sendable {
    case none
    case summary
    case full
}

public struct AITelemetryRedaction: Sendable {
    public var prompts: AITelemetryCaptureMode
    public var responses: AITelemetryCaptureMode
    public var toolArguments: AITelemetryCaptureMode
    public var toolResults: AITelemetryCaptureMode
    public var embeddingInputs: AITelemetryCaptureMode
    public var embeddingVectors: AITelemetryCaptureMode
    public var allowedHeaderNames: Set<String>

    public static let `default`: AITelemetryRedaction

    public init(
        prompts: AITelemetryCaptureMode = .summary,
        responses: AITelemetryCaptureMode = .summary,
        toolArguments: AITelemetryCaptureMode = .summary,
        toolResults: AITelemetryCaptureMode = .summary,
        embeddingInputs: AITelemetryCaptureMode = .summary,
        embeddingVectors: AITelemetryCaptureMode = .none,
        allowedHeaderNames: Set<String> = []
    )
}

public struct AITelemetryEvent: Sendable {
    public let timestamp: Date
    public let operationID: String
    public let parentOperationID: String?
    public let operationKind: AIOperationKind
    public let kind: AITelemetryEventKind

    public init(
        timestamp: Date,
        operationID: String,
        parentOperationID: String? = nil,
        operationKind: AIOperationKind,
        kind: AITelemetryEventKind
    )
}

public enum AIOperationKind: String, Sendable {
    case completion
    case stream
    case structuredOutput
    case toolLoop
    case embedding
}

public enum AITelemetryEventKind: Sendable {
    case requestStarted(AIGenerationRequestSnapshot, attempt: Int)
    case responseReceived(AIResponseSnapshot)
    case requestFailed(error: AIError, attempt: Int, metrics: AITelemetryMetrics?)
    case streamEvent(AIStreamEvent)
    case streamCompleted(finishReason: AIFinishReason?, metrics: AITelemetryMetrics?, accounting: AIAccounting?)
    case retryScheduled(attempt: Int, delay: TimeInterval, error: AIError)
    case toolApprovalRequested(AIToolCallSnapshot)
    case toolExecutionStarted(AIToolCallSnapshot)
    case toolExecutionFinished(AIToolResultSnapshot)
    case toolStepComplete(
        stepIndex: Int,
        toolCalls: [AIToolCallSnapshot],
        toolResults: [AIToolResultSnapshot],
        metrics: AITelemetryMetrics?,
        accounting: AIAccounting?
    )
    case embeddingStarted(AIEmbeddingRequestSnapshot)
    case embeddingResponse(AIEmbeddingResponseSnapshot)
    case cancelled
}

public struct AITelemetryMetrics: Sendable {
    public let totalDuration: Duration?
    public let firstEventLatency: Duration?
    public let retryCount: Int
    public let streamEventCount: Int
    public let toolCallCount: Int

    public init(
        totalDuration: Duration? = nil,
        firstEventLatency: Duration? = nil,
        retryCount: Int = 0,
        streamEventCount: Int = 0,
        toolCallCount: Int = 0
    )
}

public struct AIAccounting: Sendable {
    public let usage: AIUsage?
    public let providerReportedCost: AIReportedCost?

    public init(usage: AIUsage? = nil, providerReportedCost: AIReportedCost? = nil)
}

public struct AIReportedCost: Sendable {
    public let amount: Decimal
    public let currencyCode: String
    public let source: String?

    public init(amount: Decimal, currencyCode: String, source: String? = nil)
}

public struct AIGenerationRequestSnapshot: Sendable {
    public let model: AIModel
    public let systemPrompt: String?
    public let messages: [AIMessageSnapshot]
    public let toolNames: [String]
    public let toolChoice: AIToolChoice?
    public let allowParallelToolCalls: Bool?
    public let responseFormat: AIResponseFormatKind
    public let maxTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let stopSequences: [String]
    public let metadata: [String: String]
    public let headers: [String: String]
}

public struct AIMessageSnapshot: Sendable {
    public let role: AIRole
    public let content: [AIContentSnapshot]
}

public struct AIContentSnapshot: Sendable {
    public let kind: AIContentKind
    public let text: String?
    public let mediaType: String?
    public let toolName: String?
    public let toolUseID: String?
}

public enum AIContentKind: String, Sendable, Hashable {
    case text
    case image
    case document
    case toolUse
    case toolResult
}

public enum AIResponseFormatKind: String, Sendable {
    case text
    case json
    case jsonSchema
}

public struct AIResponseSnapshot: Sendable {
    public let id: String
    public let model: String
    public let content: [AIContentSnapshot]
    public let finishReason: AIFinishReason
    public let warnings: [AIProviderWarning]
    public let metrics: AITelemetryMetrics?
    public let accounting: AIAccounting?
}

public struct AIToolCallSnapshot: Sendable {
    public let id: String
    public let name: String
    public let inputJSON: String?
}

public struct AIToolResultSnapshot: Sendable {
    public let toolUseID: String
    public let content: String?
    public let isError: Bool
}

public struct AIEmbeddingRequestSnapshot: Sendable {
    public let model: AIModel
    public let inputs: [AIEmbeddingInputSnapshot]
    public let dimensions: Int?
    public let headers: [String: String]
    public let batchIndex: Int?
    public let batchCount: Int?
}

public struct AIEmbeddingInputSnapshot: Sendable {
    public let kind: AIEmbeddingInputKind
    public let text: String?
}

public struct AIEmbeddingResponseSnapshot: Sendable {
    public let model: String
    public let embeddings: [AIEmbeddingVectorSnapshot]
    public let warnings: [AIProviderWarning]
    public let metrics: AITelemetryMetrics?
    public let accounting: AIAccounting?
    public let batchIndex: Int?
    public let batchCount: Int?
}

public struct AIEmbeddingVectorSnapshot: Sendable {
    public let index: Int
    public let dimensions: Int
    public let vector: [Float]?
}

public func withTelemetry(
    _ provider: any AIProvider,
    configuration: AITelemetryConfiguration
) -> any AIProvider
```

## Usage

```swift
public actor ConsoleSink: AITelemetrySink {
    public func record(_ event: AITelemetryEvent) async {
        print("[\(event.operationKind.rawValue)] \(event.kind)")
    }
}

let observed = withTelemetry(
    OpenAIProvider(apiKey: "sk-..."),
    configuration: .init(sinks: [ConsoleSink()])
)

let response = try await observed.complete(
    AIRequest(model: .gpt(.gpt4oMini), messages: [.user("hello")])
)
```

## Implementation Details

### Event Ordering

Per operation, sinks observe events in causal order.

Completion flow:

1. `.requestStarted`
2. zero or more `.retryScheduled`
3. `.responseReceived` or `.requestFailed` or `.cancelled`

Streaming flow:

1. `.requestStarted`
2. zero or more `.retryScheduled` before the first stream event only
3. zero or more `.streamEvent`
4. `.streamCompleted` on success
5. terminal `.requestFailed` or `.cancelled` is emitted if the stream ends in error or cancellation

Tool-loop flow:

- The outer user call has `operationKind == .toolLoop`.
- Each underlying model request gets a child operation ID with `parentOperationID` set to the tool-loop operation.
- Tool approval, execution, result, and step-complete events are emitted on the outer operation.

Embedding flow:

- A single `embed(_:)` call emits one `.embeddingStarted` and one terminal `.embeddingResponse` or `.requestFailed`/`.cancelled`.
- `embedMany(...)` emits a parent embedding operation plus child batch operations when the helper splits requests.

### Redaction Rules

Redaction is applied before events are emitted.

- `.none` removes the sensitive field entirely.
- `.summary` keeps structure and counts but not the full payload.
- `.full` preserves the full value.

Defaults:

- prompt and response text default to `.summary`
- tool arguments and tool results default to `.summary`
- embedding vectors default to `.none`
- headers are opt-in by name through `allowedHeaderNames`

Security rules:

- Never emit authorization headers, API keys, or bearer tokens unless a caller explicitly and knowingly whitelists them. The default configuration must not do so.
- `.summary` mode for text should preserve high-level structure but not full body content.
- `.summary` mode for embeddings keeps `dimensions` only, not raw vector values.

### Metrics Surfaces

`AITelemetryMetrics` is intentionally small and derivable:

- `totalDuration`: end-to-end wall-clock latency for the observed operation
- `firstEventLatency`: time to first streamed event or first tool/embedding result when meaningful
- `retryCount`: retries actually attempted
- `streamEventCount`: number of forwarded `AIStreamEvent`s
- `toolCallCount`: number of tool calls executed in the observed scope

Metrics rules:

- Metrics are optional because not every event type has a meaningful value.
- Child batch and child tool-request operations get their own metrics.
- Parent operations may also emit aggregate metrics when that aggregate is well-defined.

### Cost and Accounting Exposure

`AIAccounting` exists to expose usage and optional provider-reported cost without hardcoding pricing tables.

Rules:

- `usage` comes from `AIUsage` and is the primary accounting surface.
- `providerReportedCost` is optional and only populated when a provider or middleware can provide authoritative cost data.
- `AICore` does not ship built-in pricing tables or token-price estimators in v1.
- Callers that want estimated cost from token usage can implement that in a telemetry sink or middleware using out-of-band pricing data.

### Complement to Middleware

Telemetry and middleware have different jobs:

- middleware may transform requests, short-circuit, cache, or apply defaults
- telemetry observes redacted snapshots and timing after the request shape is finalized
- telemetry must never mutate requests, responses, or streams

Practical guidance:

- `LoggingMiddleware` remains the easiest human-readable hook for apps that only want text logs.
- telemetry is the structured hook for metrics, tracing, analytics, and auditing.
- `LoggingMiddleware` may be implemented on top of the same internal event source, but telemetry must still work when no logging middleware is installed.

### Cancellation and Failures

- Cancellation emits `.cancelled` once for the affected operation and no later success event.
- If a raw provider stream fails after emitting one or more stream events, telemetry surfaces the same final failure the caller sees, typically `AIError.streamInterrupted`.
- Telemetry sinks do not throw. A sink that fails internally must handle its own failure and must not fail the AI operation.

## File Layout

```
Sources/AICore/
└── Observability/
    ├── AIAccounting.swift
    ├── AITelemetry.swift
    ├── AITelemetryEvent.swift
    ├── AITelemetryMetrics.swift
    └── AITelemetryRedaction.swift
```

## DocC Article Outline

### `Observability.md`

Suggested sections:

1. Telemetry vs middleware: different jobs, same pipeline.
2. Minimal sink example.
3. Safe redaction defaults and how to override them.
4. Metrics and accounting exposure.
5. Observing streaming, tools, and embeddings.

Starter examples:

```swift
public actor RecordingSink: AITelemetrySink {
    public private(set) var events: [AITelemetryEvent] = []

    public func record(_ event: AITelemetryEvent) async {
        events.append(event)
    }
}

let sink = RecordingSink()
let provider = withTelemetry(
    OpenAIProvider(apiKey: "sk-..."),
    configuration: .init(sinks: [sink])
)
```

```swift
let provider = withTelemetry(
    OpenAIProvider(apiKey: "sk-..."),
    configuration: .init(
        sinks: [sink],
        redaction: .init(prompts: .none, responses: .summary)
    )
)
```

## Opt-In Integration Test Guidance

Recommended live-test placement:

- `Tests/AICoreTests/Integration/TelemetryIntegrationTests.swift`
- `Tests/AIProviderOpenAITests/Integration/OpenAITelemetryIntegrationTests.swift`
- `Tests/AIProviderAnthropicTests/Integration/AnthropicTelemetryIntegrationTests.swift`

Rules:

- Gate live telemetry tests behind `AI_INTEGRATION_TESTS=1` plus the relevant non-empty provider API key.
- Use an actor-backed recording sink and assert event ordering rather than backend log output.
- For default redaction, assert that secrets and full prompt bodies are not exposed.
- For streaming tests, assert `.requestStarted` -> `.streamEvent` -> terminal completion/failure ordering.
- For embeddings telemetry, use OpenAI and assert `.embeddingStarted` plus terminal `.embeddingResponse`.
- Do not assert exact token counts, exact timing, or provider-generated text.

## Tests

1. `withTelemetry(...)` preserves the wrapped provider's completion result.
2. Completion requests emit `.requestStarted` then `.responseReceived` in order.
3. Streaming requests emit `.requestStarted`, redacted `.streamEvent`s, and terminal `.streamCompleted` in order.
4. Stream failures after partial output emit a terminal failure that matches the surfaced `AIError`.
5. Retry backoff emits `.retryScheduled` before the next attempt starts.
6. Tool loops emit approval, execution, result, and step-complete events on the outer operation.
7. Structured-output retries emit child request events and retry events.
8. `embedMany(...)` emits child batch events plus a final aggregated embedding response event.
9. Default redaction does not expose full prompt text.
10. Default redaction does not expose raw embedding vectors.
11. Whitelisted headers are preserved and non-whitelisted headers are removed.
12. Metrics surfaces include total duration and retry counts when applicable.
13. Usage/accounting surfaces are attached to terminal response events when enabled.
14. Providers or middleware may attach authoritative reported cost without requiring SDK pricing tables.
15. Cancellation emits `.cancelled` and no later success event.
16. Sink-internal failure does not fail the underlying AI operation.

## Acceptance Criteria

- [ ] `AICore` exposes structured telemetry through `AITelemetrySink`, `AITelemetryEvent`, and `withTelemetry(...)`.
- [ ] Request, response, stream, retry, tool, and embedding events are all covered.
- [ ] Telemetry is explicitly complementary to middleware, not a replacement for it.
- [ ] Redaction defaults are safe for prompts, tool payloads, and embedding vectors.
- [ ] Metrics surfaces are defined without requiring a specific metrics backend.
- [ ] Usage and optional provider-reported cost are exposed through `AIAccounting`.
- [ ] v1 does not commit to built-in pricing tables or SDK-maintained cost estimation.
- [ ] Cancellation and stream interruption semantics are reflected in emitted events.
- [ ] The spec includes a DocC article outline and opt-in live-test guidance for telemetry.
- [ ] All 16 test cases pass.
