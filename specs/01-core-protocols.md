# Spec 01: Core Protocols & Message Types

> The abstraction layer. Zero provider-specific HTTP code, zero third-party dependencies. Everything else builds on this.

## Goal

Define the public API surface that all providers implement and all consumers program against. A developer should be able to write their AI integration against these types, then swap providers with a one-line change.

This spec also defines the capability hooks and concurrency contracts that later specs rely on. Nothing in this file may depend on provider modules or SwiftUI modules.

## Design Rules

1. `AICore` must be buildable on its own.
2. Every public type used across concurrency boundaries must compile under Swift 6 strict concurrency.
3. Provider modules must be able to construct every public output type they need without reaching into `internal` APIs.
4. System-level instructions live in `AIRequest.systemPrompt`, not in `AIRequest.messages`.
5. `AIStream` is a single-pass, single-consumer stream. Helpers consume the same underlying stream and must not be iterated concurrently.
6. Capabilities describe provider-level defaults only; model-level validation still happens in request builders and may emit warnings or throw errors.

## Public API

### Provider Protocol

```swift
/// The core abstraction. Every AI provider (Anthropic, OpenAI, and future custom providers) conforms to this.
public protocol AIProvider: Sendable {
    /// Non-streaming completion.
    func complete(_ request: AIRequest) async throws -> AIResponse

    /// Streaming completion.
    func stream(_ request: AIRequest) -> AIStream

    /// Provider-neutral embeddings.
    ///
    /// Providers without embeddings support may rely on the default implementation,
    /// which throws `AIError.unsupportedFeature`.
    func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse

    /// Which models this provider supports.
    var availableModels: [AIModel] { get }

    /// Provider-level feature flags used by AICore helpers.
    var capabilities: AIProviderCapabilities { get }
}

extension AIProvider {
    public var capabilities: AIProviderCapabilities { .default }

    public func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        throw AIError.unsupportedFeature("Embeddings are not supported by this provider")
    }
}
```

### Provider Capabilities

`AICore` must not hard-code provider-specific behavior. Instead, providers expose a capability description that structured output, warnings, and higher-level helpers can consult.

```swift
public struct AIProviderCapabilities: Sendable {
    public var instructions: AIInstructionCapabilities
    public var structuredOutput: AIStructuredOutputCapabilities
    public var inputs: AIInputCapabilities
    public var tools: AIToolCapabilities
    public var streaming: AIStreamingCapabilities
    public var embeddings: AIEmbeddingCapabilities

    public static let `default` = AIProviderCapabilities(
        instructions: .default,
        structuredOutput: .default,
        inputs: .default,
        tools: .default,
        streaming: .default,
        embeddings: .default
    )

    public init(
        instructions: AIInstructionCapabilities,
        structuredOutput: AIStructuredOutputCapabilities,
        inputs: AIInputCapabilities,
        tools: AIToolCapabilities,
        streaming: AIStreamingCapabilities,
        embeddings: AIEmbeddingCapabilities
    )
}

public struct AIInstructionCapabilities: Sendable {
    public var defaultFormat: AIInstructionFormat
    public var reasoningModelFormatOverride: AIInstructionFormat?
    public var reasoningModelIDs: Set<AIModel>

    public static let `default` = AIInstructionCapabilities(
        defaultFormat: .message(role: .system),
        reasoningModelFormatOverride: nil,
        reasoningModelIDs: []
    )

    public init(
        defaultFormat: AIInstructionFormat,
        reasoningModelFormatOverride: AIInstructionFormat? = nil,
        reasoningModelIDs: Set<AIModel> = []
    )
}

public enum AIInstructionFormat: Sendable {
    case topLevelSystemPrompt
    case message(role: AIInstructionRole)
}

When a request is built, `reasoningModelFormatOverride` applies only when `request.model` is in `reasoningModelIDs`; otherwise `defaultFormat` is used.

public enum AIInstructionRole: String, Sendable {
    case system
    case developer
}

public struct AIStructuredOutputCapabilities: Sendable {
    public var supportsJSONMode: Bool
    public var supportsJSONSchema: Bool
    public var defaultStrategy: AIStructuredOutputStrategy

    public static let `default` = AIStructuredOutputCapabilities(
        supportsJSONMode: false,
        supportsJSONSchema: false,
        defaultStrategy: .promptInjection
    )

    public init(
        supportsJSONMode: Bool,
        supportsJSONSchema: Bool,
        defaultStrategy: AIStructuredOutputStrategy
    )
}

public enum AIStructuredOutputStrategy: Sendable {
    case providerNative
    case toolCallFallback
    case promptInjection
}

public struct AIInputCapabilities: Sendable {
    public var supportsImages: Bool
    public var supportsDocuments: Bool
    public var supportedImageMediaTypes: Set<String>
    public var supportedDocumentMediaTypes: Set<String>

    public static let `default` = AIInputCapabilities(
        supportsImages: false,
        supportsDocuments: false,
        supportedImageMediaTypes: [],
        supportedDocumentMediaTypes: []
    )

    public init(
        supportsImages: Bool,
        supportsDocuments: Bool,
        supportedImageMediaTypes: Set<String> = [],
        supportedDocumentMediaTypes: Set<String> = []
    )
}

public struct AIToolCapabilities: Sendable {
    public var supportsParallelCalls: Bool
    public var supportsForcedToolChoice: Bool

    public static let `default` = AIToolCapabilities(supportsParallelCalls: true, supportsForcedToolChoice: false)

    public init(supportsParallelCalls: Bool, supportsForcedToolChoice: Bool)
}

public struct AIStreamingCapabilities: Sendable {
    public var includesUsageInStream: Bool

    public static let `default` = AIStreamingCapabilities(includesUsageInStream: false)

    public init(includesUsageInStream: Bool)
}

public struct AIEmbeddingCapabilities: Sendable {
    public var supportsEmbeddings: Bool
    public var supportedInputKinds: Set<AIEmbeddingInputKind>
    public var supportsBatchInputs: Bool
    public var supportsDimensionOverride: Bool
    public var maxInputsPerRequest: Int?

    public static let `default` = AIEmbeddingCapabilities(
        supportsEmbeddings: false,
        supportedInputKinds: [],
        supportsBatchInputs: false,
        supportsDimensionOverride: false,
        maxInputsPerRequest: nil
    )

    public init(
        supportsEmbeddings: Bool,
        supportedInputKinds: Set<AIEmbeddingInputKind>,
        supportsBatchInputs: Bool,
        supportsDimensionOverride: Bool,
        maxInputsPerRequest: Int? = nil
    )
}

public enum AIEmbeddingInputKind: String, Sendable, Hashable {
    case text
}
```

Capabilities are the provider-level source of truth for high-level helper behavior. They do not replace per-model request validation. A provider may advertise `supportsJSONSchema == true`, `supportsEmbeddings == true`, or `supportsDocuments == true` and still emit warnings or `AIError.unsupportedFeature` for specific model families or media types.

### Request & Response

```swift
/// A single request to an AI provider.
public struct AIRequest: Sendable {
    public var model: AIModel
    public var messages: [AIMessage]

    /// Provider-neutral system or developer instructions.
    ///
    /// This is the only supported place for top-level instructions. `messages`
    /// must not contain `.system` messages.
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
    )
}

/// The response from a completed (non-streaming) call.
public struct AIResponse: Sendable {
    public let id: String
    public let content: [AIContent]
    public let model: String
    public let usage: AIUsage
    public let finishReason: AIFinishReason
    public let warnings: [AIProviderWarning]

    public init(
        id: String,
        content: [AIContent],
        model: String,
        usage: AIUsage,
        finishReason: AIFinishReason,
        warnings: [AIProviderWarning] = []
    )

    /// Convenience: the concatenated text content.
    public var text: String { get }
}

public struct AIProviderWarning: Sendable {
    public let code: String
    public let message: String
    public let parameter: String?

    public init(code: String, message: String, parameter: String? = nil)
}

public struct AIUsage: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let inputTokenDetails: InputTokenDetails?
    public let outputTokenDetails: OutputTokenDetails?

    public init(
        inputTokens: Int,
        outputTokens: Int,
        inputTokenDetails: InputTokenDetails? = nil,
        outputTokenDetails: OutputTokenDetails? = nil
    )

    public var totalTokens: Int { inputTokens + outputTokens }

    public struct InputTokenDetails: Sendable {
        public let cachedTokens: Int?
        public let cacheWriteTokens: Int?

        public init(cachedTokens: Int? = nil, cacheWriteTokens: Int? = nil)
    }

    public struct OutputTokenDetails: Sendable {
        public let reasoningTokens: Int?

        public init(reasoningTokens: Int? = nil)
    }
}

public enum AIFinishReason: Sendable {
    case stop
    case stopSequence(String?)
    case maxTokens
    case toolUse
    case contentFilter
    case refusal
    case pauseTurn
    case unknown(String)
}
```

### Messages

```swift
public struct AIMessage: Sendable {
    public let role: AIRole
    public let content: [AIContent]

    public init(role: AIRole, content: [AIContent])

    public static func user(_ text: String) -> AIMessage
    public static func user(_ content: [AIContent]) -> AIMessage
    public static func assistant(_ text: String) -> AIMessage
    public static func assistant(_ content: [AIContent]) -> AIMessage
    public static func tool(id: String, content: String) -> AIMessage
}

public enum AIRole: String, Sendable, Codable {
    case user
    case assistant
    case tool
}

public enum AIContent: Sendable {
    case text(String)
    case image(AIImage)
    case document(AIDocument)
    case toolUse(AIToolUse)
    case toolResult(AIToolResult)
}

public struct AIImage: Sendable {
    public let data: Data
    public let mediaType: AIMediaType

    public init(data: Data, mediaType: AIMediaType)

    public enum AIMediaType: String, Sendable {
        case jpeg = "image/jpeg"
        case png = "image/png"
        case gif = "image/gif"
        case webp = "image/webp"
    }

    /// Load from a local file URL.
    public static func from(fileURL: URL) throws -> AIImage

    /// Load from a base64 string.
    public static func from(base64: String, mediaType: AIMediaType) throws -> AIImage
}

public struct AIDocument: Sendable {
    public let data: Data
    public let mediaType: AIMediaType
    public let filename: String?

    public init(data: Data, mediaType: AIMediaType, filename: String? = nil)

    public enum AIMediaType: String, Sendable {
        case pdf = "application/pdf"
        case plainText = "text/plain"
    }

    public static func from(fileURL: URL, mediaType: AIMediaType? = nil) throws -> AIDocument
    public static func from(base64: String, mediaType: AIMediaType, filename: String? = nil) throws -> AIDocument
}
```

Input extensibility rules:

- v1 ships a conservative set of core image and document media types.
- Providers advertise their concrete MIME-type support through `AIInputCapabilities.supportedImageMediaTypes` and `supportedDocumentMediaTypes`.
- If a caller supplies a core media type that a selected provider or model does not support, the SDK should emit an `AIProviderWarning` or throw `AIError.unsupportedFeature` before network I/O.
- Future file types are additive. Extending MIME-type coverage must not change transcript semantics or require a new message role.

### Models

```swift
/// A model identifier. Providers define their own static constants.
public struct AIModel: Sendable, Hashable {
    public let id: String
    public let provider: String?

    public init(_ id: String, provider: String? = nil)
}

// Provider-specific model constants are defined in each provider module:
// e.g. AIModel.claude(.sonnet4_5), AIModel.gpt(.gpt4o)
```

Model discovery note:

- `availableModels` is informational and may include both generation and embedding models.
- Callers must not infer per-operation support from model naming alone; the selected request builder and model-level validation remain authoritative.

### Embeddings

```swift
public struct AIEmbeddingRequest: Sendable {
    public var model: AIModel
    public var inputs: [AIEmbeddingInput]
    public var dimensions: Int?
    public var retryPolicy: RetryPolicy
    public var timeout: AITimeout
    public var headers: [String: String]

    public init(
        model: AIModel,
        inputs: [AIEmbeddingInput],
        dimensions: Int? = nil,
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default,
        headers: [String: String] = [:]
    )
}

public enum AIEmbeddingInput: Sendable {
    case text(String)
}

public struct AIEmbeddingResponse: Sendable {
    public let model: String
    public let embeddings: [AIEmbedding]
    public let usage: AIUsage?
    public let warnings: [AIProviderWarning]

    public init(
        model: String,
        embeddings: [AIEmbedding],
        usage: AIUsage? = nil,
        warnings: [AIProviderWarning] = []
    )
}

public struct AIEmbedding: Sendable {
    public let index: Int
    public let vector: [Float]

    public init(index: Int, vector: [Float])

    public var dimensions: Int { vector.count }
}
```

Embeddings contract:

- v1 supports text embeddings only through `AIEmbeddingInput.text`.
- `AIUsage.outputTokens` is always `0` for embedding responses.
- `embedMany(...)` preserves the caller's input order even when it has to split work into multiple provider requests.
- Embeddings are non-streaming in v1.

### Streaming

```swift
/// A single-pass async sequence of stream events.
///
/// Important: `AIStream` is single-consumer. Iterate the raw stream OR one of its
/// derived helpers, but never more than one at the same time.
public struct AIStream: AsyncSequence, Sendable {
    public typealias Element = AIStreamEvent
    public typealias AsyncIterator = AsyncThrowingStream<AIStreamEvent, AIError>.Iterator

    public init(_ stream: AsyncThrowingStream<AIStreamEvent, AIError>)
    public func makeAsyncIterator() -> AsyncIterator
}

public enum AIStreamEvent: Sendable {
    case start(id: String, model: String)
    case delta(AIStreamDelta)
    case toolUseStart(id: String, name: String)
    case usage(AIUsage)
    case finish(AIFinishReason)
}

public enum AIStreamDelta: Sendable {
    case text(String)
    case toolInput(id: String, jsonDelta: String)
}

extension AIStream {
    /// Collects the full streamed response into an `AIResponse`.
    public func collect() async throws -> AIResponse

    /// Yields only text deltas as they arrive.
    public var textStream: AsyncThrowingStream<String, AIError> { get }

    /// Accumulates text, yielding the running total at each step.
    public var accumulatedText: AsyncThrowingStream<String, AIError> { get }
}
```

Implementation contract:

- `AIStream` wraps `AsyncThrowingStream<AIStreamEvent, AIError>`.
- Errors are delivered only by throwing termination, never by an in-band `.error` event.
- `toolUseStart` announces only the tool id and name; the full JSON input is assembled from subsequent `.delta(.toolInput(...))` events.
- `collect()`, `textStream`, and `accumulatedText` consume the same underlying stream.
- If the stream throws after emitting partial content, `collect()` throws and does not synthesize a partial `AIResponse`.

Stream interruption policy:

- If a started stream ends without a terminal `.finish`, surface `AIError.streamInterrupted` unless a more specific mapped `AIError` is available.
- If interruption happens before the first yielded event, normal retry rules still apply.
- v1 never attempts mid-stream resumption or silent replay.
- Recovery means issuing a fresh request with the committed transcript outside the interrupted stream.

### Tools

```swift
/// Defines a tool the model can call.
public struct AITool: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: AIJSONSchema
    public let handler: @Sendable (Data) async throws -> String
    public let needsApproval: Bool

    public init(
        name: String,
        description: String,
        inputSchema: AIJSONSchema,
        needsApproval: Bool = false,
        handler: @escaping @Sendable (Data) async throws -> String
    )
}

public enum AIToolChoice: Sendable {
    case auto
    case required
    case none
    case tool(String)
}

/// A tool call from the model.
public struct AIToolUse: Sendable {
    public let id: String
    public let name: String
    public let input: Data

    public init(id: String, name: String, input: Data)
}

/// Result of executing a tool.
public struct AIToolResult: Sendable {
    public let toolUseId: String
    public let content: String
    public let isError: Bool

    public init(toolUseId: String, content: String, isError: Bool = false)
}

/// JSON Schema representation for tool inputs and structured output.
public indirect enum AIJSONSchema: Sendable, Codable {
    case string(description: String? = nil, enumValues: [String]? = nil, format: String? = nil)
    case number(description: String? = nil)
    case integer(description: String? = nil)
    case boolean(description: String? = nil)
    case object(
        properties: [String: AIJSONSchema],
        required: [String],
        additionalProperties: Bool = false,
        description: String? = nil
    )
    case array(items: AIJSONSchema, description: String? = nil)
    case oneOf([AIJSONSchema], description: String? = nil)
    case ref(String)
    case null

    public static var anyJSON: AIJSONSchema { get }
}
```

### Structured Output / Response Format

```swift
public enum AIResponseFormat: Sendable {
    case text
    case json
    case jsonSchema(AIJSONSchema)
}
```

Normalization rule:

- `.json` means "return valid arbitrary JSON".
- If a provider does not expose a dedicated JSON-object mode but does expose schema mode, higher-level helpers or provider request builders may normalize `.json` to `.jsonSchema(.anyJSON)` before the request is serialized.
- That normalization must preserve user intent and should not require prompt injection when native schema mode is available.

### Errors

```swift
public struct AIErrorContext: Error, Sendable {
    public let message: String
    public let underlyingType: String?

    public init(message: String, underlyingType: String? = nil)
}

public enum AIError: Error, Sendable {
    case invalidRequest(String)
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case modelNotFound(String)
    case contentFiltered
    case serverError(statusCode: Int, message: String)
    case networkError(AIErrorContext)
    case decodingError(AIErrorContext)
    case streamInterrupted
    case timeout(AITimeoutKind)
    case cancelled
    case maxRetriesExceeded(attempts: Int, lastError: AIErrorContext)
    case noContentGenerated
    case unsupportedFeature(String)
    case unknown(AIErrorContext)
}

public enum AITimeoutKind: Sendable {
    case total
    case step
    case chunk
}
```

### Retry Policy

```swift
public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var initialDelay: TimeInterval
    public var backoffMultiplier: Double
    public var maxDelay: TimeInterval

    public static let `default` = RetryPolicy(
        maxRetries: 2,
        initialDelay: 2.0,
        backoffMultiplier: 2.0,
        maxDelay: 60.0
    )

    public static let none = RetryPolicy(maxRetries: 0, initialDelay: 0, backoffMultiplier: 1, maxDelay: 0)

    public init(maxRetries: Int, initialDelay: TimeInterval, backoffMultiplier: Double, maxDelay: TimeInterval)
}
```

Retry contract:

- Retryable: 408, 409, 429, and 500+ responses.
- Never retry: 400/401/404 class request errors, validation errors, decode errors, unsupported-feature errors, or cancellations.
- `retry-after-ms` takes precedence over `retry-after`.
- The actual delay is `max(serverDelay, exponentialDelay)` when the server delay is in range.
- Automatic retry is allowed only before the first streamed event is yielded.
- Once a stream has emitted any event, or once a tool has executed in a tool loop, automatic retry stops and the error is surfaced immediately.
- Retry executors must check for task cancellation before each attempt and during any backoff sleep.

### Cancellation Contract

- Cancelling the parent task must cancel active transport work, pending retry sleeps, any helper-created child tasks, and any unfinished embedding batches.
- Providers should map transport-side cancellation to `AIError.cancelled`; higher-level UI helpers may choose to treat that as a clean stop.
- After cancellation is observed, streams must stop yielding new upstream events immediately and helper APIs must not synthesize extra finish, retry, or tool events. Helper transforms may flush already-buffered derived text once before terminating.

### Rate-Limiting Guidance

- `AIError.rateLimited(retryAfter:)` is the canonical surfaced error.
- Retry policy handles per-request backoff only; v1 does not define a built-in process-wide concurrency limiter or token bucket.
- Applications that need tenant- or app-wide throttling should layer it above the provider or in middleware.
- When providers expose `retry-after` information, logging and telemetry surfaces should preserve it rather than collapsing it into an opaque generic error.

### Timeout Configuration

```swift
public struct AITimeout: Sendable {
    public var total: TimeInterval?
    public var step: TimeInterval?
    public var chunk: TimeInterval?

    public static let `default` = AITimeout(total: nil, step: nil, chunk: nil)

    public init(total: TimeInterval? = nil, step: TimeInterval? = nil, chunk: TimeInterval? = nil)
}
```

### Transport Support

Use a transport abstraction instead of relying on `URLProtocol` for all provider tests. This makes streaming tests deterministic under async/await and avoids global state.

```swift
public protocol AIHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func stream(for request: URLRequest) async throws -> AIHTTPStreamResponse
}

public struct AIHTTPStreamResponse: Sendable {
    public let response: HTTPURLResponse
    public let body: AsyncThrowingStream<Data, AIError>

    public init(response: HTTPURLResponse, body: AsyncThrowingStream<Data, AIError>)
}

public struct URLSessionTransport: AIHTTPTransport, Sendable {
    public init(session: URLSession = .shared)
}

public struct AIProviderHTTPConfiguration: Sendable {
    public var baseURL: URL?
    public var transport: any AIHTTPTransport
    public var defaultHeaders: [String: String]

    public init(
        baseURL: URL? = nil,
        transport: any AIHTTPTransport,
        defaultHeaders: [String: String] = [:]
    )
}
```

`AICore` defines the abstraction only. Provider modules supply the default `URLSession`-backed transport.

### Provider Configuration Guidance

Cross-request configuration belongs on provider initializers or `AIProviderHTTPConfiguration`; per-call knobs stay on `AIRequest` and `AIEmbeddingRequest`.

Rules:

- Typed initializer parameters are appropriate for stable provider concepts like `apiKey`, `baseURL`, `organization`, and custom transport.
- Experimental or vendor-specific opt-ins stay in `defaultHeaders` or request `headers` until they prove stable enough for a first-class API.
- Capability-driven behavior must never require callers to downcast a provider to an implementation type just to discover feature support.

### Middleware

```swift
public protocol AIMiddleware: Sendable {
    func transformRequest(_ request: AIRequest) async throws -> AIRequest

    func transformEmbeddingRequest(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingRequest

    func wrapGenerate(
        request: AIRequest,
        next: @Sendable (AIRequest) async throws -> AIResponse
    ) async throws -> AIResponse

    func wrapStream(
        request: AIRequest,
        next: @Sendable (AIRequest) -> AIStream
    ) -> AIStream

    func wrapEmbed(
        request: AIEmbeddingRequest,
        next: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    ) async throws -> AIEmbeddingResponse
}

extension AIMiddleware {
    public func transformRequest(_ request: AIRequest) async throws -> AIRequest { request }

    public func transformEmbeddingRequest(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingRequest { request }

    public func wrapGenerate(
        request: AIRequest,
        next: @Sendable (AIRequest) async throws -> AIResponse
    ) async throws -> AIResponse {
        try await next(request)
    }

    public func wrapStream(
        request: AIRequest,
        next: @Sendable (AIRequest) -> AIStream
    ) -> AIStream {
        next(request)
    }

    public func wrapEmbed(
        request: AIEmbeddingRequest,
        next: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    ) async throws -> AIEmbeddingResponse {
        try await next(request)
    }
}

public func withMiddleware(
    _ provider: any AIProvider,
    middleware: [any AIMiddleware]
) -> any AIProvider
```

Composition rules:

- Middlewares are applied in array order.
- `transformRequest` runs before `wrapGenerate` / `wrapStream`.
- `transformEmbeddingRequest` runs before `wrapEmbed`.
- Middleware may short-circuit and return cached results.
- Middleware must never retry after a stream has emitted any event.

Built-in middlewares:

| Middleware | Purpose |
|-----------|---------|
| `LoggingMiddleware` | Logs generation, streaming, and embedding requests, responses, warnings, and timing |
| `DefaultSettingsMiddleware` | Applies generation defaults like temperature, maxTokens, and tool choice without mutating unrelated embedding fields |

### Convenience API (built on the protocol)

```swift
extension AIProvider {
    public func complete(
        _ prompt: String,
        model: AIModel,
        systemPrompt: String? = nil
    ) async throws -> String

    public func stream(
        _ prompt: String,
        model: AIModel,
        systemPrompt: String? = nil
    ) -> AIStream

    public func complete(
        messages: [AIMessage],
        model: AIModel,
        systemPrompt: String? = nil
    ) async throws -> AIResponse

    public func embed(
        _ text: String,
        model: AIModel,
        dimensions: Int? = nil,
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default,
        headers: [String: String] = [:]
    ) async throws -> AIEmbedding

    public func embedMany(
        _ texts: [String],
        model: AIModel,
        dimensions: Int? = nil,
        batchSize: Int? = nil,
        retryPolicy: RetryPolicy = .default,
        timeout: AITimeout = .default,
        headers: [String: String] = [:]
    ) async throws -> AIEmbeddingResponse
}
```

## File Layout

```
Sources/AICore/
├── Provider/
│   ├── AIProvider.swift
│   └── AIProviderCapabilities.swift
├── Request/
│   ├── AIRequest.swift
│   └── AIResponseFormat.swift
├── Response/
│   ├── AIResponse.swift
│   ├── AIUsage.swift
│   └── AIProviderWarning.swift
├── Messages/
│   ├── AIMessage.swift
│   ├── AIRole.swift
│   ├── AIContent.swift
│   ├── AIImage.swift
│   └── AIDocument.swift
├── Models/
│   └── AIModel.swift
├── Embeddings/
│   ├── AIEmbedding.swift
│   ├── AIEmbeddingRequest.swift
│   └── AIEmbeddingResponse.swift
├── Streaming/
│   ├── AIStream.swift
│   ├── AIStreamEvent.swift
│   ├── AIStreamDelta.swift
│   └── SmoothStreaming.swift
├── Tools/
│   ├── AITool.swift
│   ├── AIToolChoice.swift
│   ├── AIToolUse.swift
│   ├── AIToolResult.swift
│   ├── AIToolExecution.swift
│   ├── AIToolResponse.swift
│   ├── AIToolStream.swift
│   └── StopCondition.swift
├── StructuredOutput/
│   ├── AIStructured.swift
│   ├── AIStructuredResponse.swift
│   ├── AIJSONSchema.swift
│   ├── AIJSONSchemaGenerator.swift
│   ├── StructuredOutputGenerator.swift
│   └── StructuredOutputRepair.swift
├── Agent/
│   └── Agent.swift
├── Retry/
│   ├── RetryPolicy.swift
│   └── RetryExecutor.swift
├── Timeout/
│   └── AITimeout.swift
├── Transport/
│   ├── AIHTTPTransport.swift
│   ├── URLSessionTransport.swift
│   └── AIProviderHTTPConfiguration.swift
├── Middleware/
│   ├── AIMiddleware.swift
│   ├── MiddlewareProvider.swift
│   ├── LoggingMiddleware.swift
│   └── DefaultSettingsMiddleware.swift
├── Observability/
│   ├── AIAccounting.swift
│   ├── AITelemetry.swift
│   ├── AITelemetryEvent.swift
│   ├── AITelemetryMetrics.swift
│   └── AITelemetryRedaction.swift
├── Documentation.docc/
│   ├── AICore.md
│   ├── GettingStarted.md
│   ├── CapabilityMatrix.md
│   ├── Embeddings.md
│   ├── Observability.md
│   ├── Providers.md
│   ├── StructuredOutput.md
│   ├── ToolUse.md
│   └── Middleware.md
└── Errors/
    └── AIError.swift
```

## Tests

All tests use a mock provider and a mock transport.

```swift
public actor MockProviderRecorder {
    public private(set) var completeCalls: [AIRequest] = []
    public private(set) var streamCalls: [AIRequest] = []
    public private(set) var embedCalls: [AIEmbeddingRequest] = []

    public func recordComplete(_ request: AIRequest)
    public func recordStream(_ request: AIRequest)
    public func recordEmbed(_ request: AIEmbeddingRequest)
}

public struct MockProvider: AIProvider, Sendable {
    public var completionHandler: @Sendable (AIRequest) async throws -> AIResponse
    public var streamHandler: @Sendable (AIRequest) -> AIStream
    public var embeddingHandler: @Sendable (AIEmbeddingRequest) async throws -> AIEmbeddingResponse
    public var availableModels: [AIModel] = []
    public var capabilities: AIProviderCapabilities = .default
    public let recorder: MockProviderRecorder

    public func complete(_ request: AIRequest) async throws -> AIResponse
    public func stream(_ request: AIRequest) -> AIStream
    public func embed(_ request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse
}

public struct MockTransport: AIHTTPTransport, Sendable {
    public var dataHandler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public var streamHandler: @Sendable (URLRequest) async throws -> AIHTTPStreamResponse

    public init(
        dataHandler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        streamHandler: @escaping @Sendable (URLRequest) async throws -> AIHTTPStreamResponse
    )
}
```

### Test cases

1. Request construction with all fields including tool choice, metadata, retry, timeout, and headers.
2. Message creation helpers produce correct role/content.
3. `.system` messages are not part of the public message model.
4. Convenience `complete("prompt", model:)` builds the correct `AIRequest`.
5. `AIResponse` and `AIUsage` public initializers are usable from another target.
6. `AIStream.collect()` assembles deltas into a full `AIResponse`.
7. `AIStream.textStream` and `accumulatedText` rethrow upstream errors.
8. `AIStream` single-consumer contract is documented and tested.
9. `AIContent.document` round-trips correctly.
10. `AIModel` equality/hashability works across constructions.
11. `response.text` concatenates all `.text` blocks.
12. `AIError` cases have useful descriptions and all associated payloads are `Sendable`.
13. `AIImage.from(fileURL:)` and `AIDocument.from(fileURL:)` work correctly.
14. `AITool` captures name, description, schema, handler, and `needsApproval`.
15. `AIToolChoice` is encoded into requests by convenience helpers.
16. `AIProviderCapabilities.default` is stable and documented.
17. Retry policy defaults and backoff calculation are correct.
18. Only retryable HTTP errors trigger retry.
19. `retry-after` / `retry-after-ms` are respected.
20. No automatic retry occurs after the first streamed event has been emitted.
21. Total timeout aborts requests.
22. Chunk timeout aborts stalled streams.
23. Middleware transforms generation and embedding requests before the provider sees them.
24. Middleware wraps completion, stream, and embed calls in the correct order.
25. Middleware short-circuiting works.
26. `LoggingMiddleware` does not mutate requests, embedding requests, or responses.
27. `DefaultSettingsMiddleware` fills in missing generation defaults only.
28. `MockTransport` supports deterministic streaming tests.
29. All public types in `AICore` compile with strict concurrency.
30. Embedding request construction supports inputs, dimensions, retry, timeout, and headers.
31. `embed("...")` builds a single-input request and returns the first embedding.
32. `embedMany(...)` preserves input order across provider batch splitting.
33. `AIEmbeddingResponse.usage` aggregates across `embedMany(...)` batches.
34. Providers without embedding support throw `AIError.unsupportedFeature` via the default `embed(_:)` implementation.
35. `AIInputCapabilities` exposes supported image and document media type sets.
36. Cancellation during retry backoff surfaces `.cancelled` promptly.
37. A stream interrupted after the first event surfaces `.streamInterrupted` without a synthetic final response.

## Acceptance Criteria

- [ ] All types compile with strict concurrency checking enabled.
- [ ] Provider modules can construct `AIResponse`, `AIEmbeddingResponse`, `AIEmbedding`, `AIUsage`, `AIProviderWarning`, `AIToolUse`, `AIToolResult`, and `AIStream` via public APIs.
- [ ] `AIProvider` defines `complete`, `stream`, `embed`, `availableModels`, and `capabilities`.
- [ ] `AIProviderCapabilities` is the only provider-specific hook `AICore` uses for structured-output and helper behavior.
- [ ] `AIProviderCapabilities` includes embeddings support metadata.
- [ ] `AIRequest.systemPrompt` is the canonical instruction channel.
- [ ] `AIRole` does not include `.system`.
- [ ] `AIStream` conforms to `AsyncSequence` and uses throwing termination as its only error channel.
- [ ] `AIStream` helper streams are `AsyncThrowingStream`, not `AsyncStream`.
- [ ] `AIEmbeddingRequest`, `AIEmbeddingResponse`, and `AIEmbedding` provide a provider-agnostic embeddings surface.
- [ ] `AIJSONSchema` is recursively representable in Swift without undefined placeholder types.
- [ ] `RetryPolicy` documents that retries stop after the first stream event or first tool side effect.
- [ ] Cancellation semantics are defined across transport, retry, streaming, and embedding helpers.
- [ ] `AITimeout` supports total, step, and chunk timeouts.
- [ ] `AIHTTPTransport` exists for provider configuration and testability.
- [ ] `URLSessionTransport` exists as the default production transport.
- [ ] `AIDocument` exists for PDF and plain-text file inputs.
- [ ] `AIInputCapabilities` advertises MIME-type-level image and document support.
- [ ] `withMiddleware()` composes middlewares in array order across completion, streaming, and embeddings.
- [ ] `LoggingMiddleware` and `DefaultSettingsMiddleware` ship as built-ins.
- [ ] `AIUsage` includes optional token detail breakdowns.
- [ ] All 37 test cases pass.
- [ ] Zero external dependencies - Foundation only.
- [ ] Package.swift defines the `AICore` library target.
