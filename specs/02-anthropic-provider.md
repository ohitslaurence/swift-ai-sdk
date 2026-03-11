# Spec 02: Anthropic Provider

> First real provider implementation. Proves the core protocols work against a real API.

## Review History

- 2026-03-11: Deep implementation audit completed. Reconciled public Claude aliases with the shipped API, tightened malformed response and stream decoding, added explicit SSE error-event mapping, expanded `Retry-After` handling, and added focused regression coverage.

## Goal

Implement `AnthropicProvider` conforming to `AIProvider`, covering the Anthropic Messages API with streaming, tool use, vision, documents, and native structured output.

Embeddings are explicitly unsupported in this provider spec until Anthropic ships a stable public embeddings endpoint.

## Dependencies

- Spec 01 (AICore)
- Foundation `URLSession` only for the default transport

## Public API

```swift
public struct AnthropicProvider: AIProvider, Sendable {
    public init(
        apiKey: String,
        baseURL: URL? = nil,
        transport: any AIHTTPTransport = URLSessionTransport(),
        defaultHeaders: [String: String] = [:]
    )

    public func complete(_ request: AIRequest) async throws -> AIResponse
    public func stream(_ request: AIRequest) -> AIStream
    public var availableModels: [AIModel] { get }
    public var capabilities: AIProviderCapabilities { get }
}

extension AIModel {
    public enum Claude {
        case opus46
        case sonnet46
        case sonnet45
        case haiku45
        case custom(String)

        public static var opus4_6: Self { get }
        public static var sonnet4_6: Self { get }
        public static var sonnet4_5: Self { get }
        public static var haiku4_5: Self { get }

        public var model: AIModel { get }
    }

    public static func claude(_ variant: Claude) -> AIModel
}
```

`AnthropicProvider` inherits the protocol's default `embed(_:)` implementation, which throws `AIError.unsupportedFeature`.

### Usage

```swift
let provider = AnthropicProvider(apiKey: "sk-ant-...")

let text = try await provider.complete("Hello", model: .claude(.haiku4_5))

for try await chunk in provider.stream("Tell me a story", model: .claude(.sonnet4_5)).textStream {
    print(chunk, terminator: "")
}

let image = try AIImage.from(fileURL: photoURL)
let response = try await provider.complete(
    AIRequest(
        model: .claude(.sonnet4_5),
        messages: [.user([.image(image), .text("What's in this image?")])]
    )
)

let document = try AIDocument.from(fileURL: pdfURL)
let summary = try await provider.complete(
    AIRequest(
        model: .claude(.sonnet4_5),
        messages: [.user([.document(document), .text("Summarize this PDF")])]
    )
)
```

## Implementation Details

### Capabilities

`AnthropicProvider.capabilities` must report:

- `instructions.defaultFormat = .topLevelSystemPrompt`
- `instructions.reasoningModelFormatOverride = nil`
- `structuredOutput.supportsJSONMode = false`
- `structuredOutput.supportsJSONSchema = true`
- `structuredOutput.defaultStrategy = .providerNative`
- `inputs.supportsImages = true`
- `inputs.supportsDocuments = true`
- `inputs.supportedImageMediaTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"]`
- `inputs.supportedDocumentMediaTypes = ["application/pdf", "text/plain"]`
- `tools.supportsParallelCalls = true`
- `tools.supportsForcedToolChoice = true`
- `streaming.includesUsageInStream = true`
- `embeddings = .default`

### API Mapping

| AICore type | Anthropic Messages API |
|-------------|------------------------|
| `AIRequest` | `POST /v1/messages` body |
| `AIRequest.systemPrompt` | Top-level `system` field |
| `AIMessage(role: .user)` | `messages[]` role `user` |
| `AIMessage(role: .assistant)` | `messages[]` role `assistant` |
| `AIMessage(role: .tool)` | Adapt to a `user` message containing one or more `tool_result` content blocks |
| `AIContent.text` | `{"type": "text", "text": "..."}` |
| `AIContent.image` | `{"type": "image", "source": {"type": "base64", ...}}` |
| `AIContent.document` | `{"type": "document", "source": {"type": "base64", ...}}` |
| `AIContent.toolUse` | `{"type": "tool_use", "id": ..., "name": ..., "input": ...}` |
| `AIContent.toolResult` | `{"type": "tool_result", "tool_use_id": ..., "content": ...}` |
| `AITool` | `tools[]` with `input_schema` |
| `AIToolChoice` | `tool_choice` |
| `allowParallelToolCalls` | `tool_choice.disable_parallel_tool_use` |
| `AIResponseFormat.json` | Normalize to `.jsonSchema(.anyJSON)` before request building |
| `AIResponseFormat.jsonSchema` | `output_config.format` |
| `maxTokens` | `max_tokens` (required - default to 4096 when nil) |
| `temperature` | `temperature` |
| `topP` | `top_p` |
| `stopSequences` | `stop_sequences` |
| `metadata` | `metadata` |

Transcript rule:

- Anthropic has no `tool` role. When `AICore` appends tool results to the transcript, the provider must serialize those messages as `user` turns containing `tool_result` content blocks.

### Structured Output

Anthropic now supports native structured output in the Messages API via `output_config.format`.

Rules:

1. `AIResponseFormat.jsonSchema` uses native `output_config.format` first.
2. If the provider receives `AIResponseFormat.json` on ordinary `complete(_:)` / `stream(_:)` calls, the Anthropic request builder normalizes it to `.jsonSchema(.anyJSON)` before serializing the request.
3. Anthropic request building currently always forwards native structured-output fields when JSON output is requested; unsupported official model IDs and custom Anthropic-compatible deployments surface warnings instead of silently falling back.
4. Even with native structured output, the SDK still validates and decodes locally.

### Embeddings

Anthropic embeddings are out of scope for the current provider surface.

Rules:

1. `AnthropicProvider.capabilities.embeddings` remains `.default`.
2. `AnthropicProvider` must not attempt unofficial or speculative embeddings endpoints.
3. Calls to `embed(_:)` fail through the default `AIError.unsupportedFeature` path before any transport work starts.

### Streaming (SSE)

Anthropic uses Server-Sent Events. Map events to `AIStreamEvent`:

| Anthropic SSE event | AIStreamEvent |
|---------------------|---------------|
| `message_start` | `.start(id:, model:)` |
| `content_block_delta` (`text_delta`) | `.delta(.text(...))` |
| `content_block_start` (`tool_use`) | `.toolUseStart(id:, name:)` |
| `content_block_delta` (`input_json_delta`) | `.delta(.toolInput(id:, jsonDelta:))` |
| `message_delta` (`usage`) | `.usage(...)` |
| final `message_delta.stop_reason` + `message_stop` | `.finish(...)` |

Notes:

- The parser must buffer the latest `stop_reason` from `message_delta` and emit a single `.finish` event when the message stops.
- Stream failures are surfaced by throwing `AIError`; there is no `.error` event.
- If the SSE connection drops after `.start` or any `.delta` and no terminal `message_stop` arrives, surface `AIError.streamInterrupted`.
- SSE `error` events must be mapped into the corresponding `AIError` immediately instead of degrading into `AIError.streamInterrupted`.

### Finish Reason Mapping

| Anthropic stop reason | AIFinishReason |
|-----------------------|----------------|
| `end_turn` | `.stop` |
| `stop_sequence` | `.stopSequence(...)` |
| `max_tokens` | `.maxTokens` |
| `tool_use` | `.toolUse` |
| `pause_turn` | `.pauseTurn` |
| `refusal` | `.refusal` |
| anything else | `.unknown(...)` |

### Error Mapping

| HTTP Status | AIError |
|-------------|---------|
| 400 | `.invalidRequest(message)` |
| 401 | `.authenticationFailed` |
| 404 | `.modelNotFound(model)` |
| 409 | `.serverError(statusCode:, message:)` |
| 429 | `.rateLimited(retryAfter:)` |
| 500+ | `.serverError(statusCode:, message:)` |
| transport failure | `.networkError(...)` |
| decode failure | `.decodingError(...)` |

### Headers

```
X-Api-Key: {apiKey}
anthropic-version: 2023-06-01
content-type: application/json
```

Notes:

- Support `anthropic-beta` only when a caller explicitly opts in through request/provider headers.
- Merge `AIRequest.headers` after provider defaults so callers can add non-auth custom headers.

### Provider Configuration Knobs

- Stable cross-request knobs are `apiKey`, `baseURL`, `transport`, and `defaultHeaders`.
- Experimental Anthropic opt-ins stay in `defaultHeaders` or `AIRequest.headers` until they become stable enough for a typed public API.
- Do not add a dedicated initializer parameter for every beta header.

### Retry Integration

The provider does not implement retry logic itself. Its job is to:

1. Map HTTP and transport failures into clean `AIError` values.
2. Parse `retry-after-ms` plus `retry-after` second or HTTP-date values into `.rateLimited(retryAfter:)` when present.
3. Surface streaming errors immediately after the first emitted event - no hidden mid-stream replay.
4. Propagate task cancellation through active transport work and pending retry backoff without emitting extra stream events.

### Unsupported Features & Warnings

- Anthropic-specific request builders remain responsible for model-level warnings and adaptations.
- If a request uses a valid core field that the selected model does not support, emit `AIProviderWarning` rather than silently dropping it.
- If a feature cannot be adapted safely, throw `AIError.unsupportedFeature`.

### Usage Mapping

Map Anthropic usage to `AIUsage`:

```
input_tokens -> inputTokens
output_tokens -> outputTokens
cache_creation_input_tokens -> inputTokenDetails.cacheWriteTokens
cache_read_input_tokens -> inputTokenDetails.cachedTokens
```

## File Layout

```
Sources/AIProviderAnthropic/
├── AnthropicProvider.swift
├── AnthropicModels.swift
├── Internal/
│   ├── AnthropicRequestBuilder.swift
│   ├── AnthropicResponseParser.swift
│   ├── AnthropicStreamParser.swift
│   └── AnthropicErrorMapper.swift
└── Documentation.docc/
    └── AnthropicProvider.md
```

## Tests

Use `MockTransport` by default. Reserve `MockURLProtocol` for `URLSessionTransport` adapter smoke tests.

1. Simple completion returns a fully populated `AIResponse`.
2. Streaming SSE emits events in order and finishes cleanly.
3. `systemPrompt` maps to top-level `system`.
4. Multi-turn conversations serialize correctly.
5. Vision requests encode base64 image content blocks correctly.
6. Document requests encode PDF/plain-text blocks correctly.
7. Tool definitions serialize as `tools[]` with `input_schema`.
8. Tool-use responses decode into `AIContent.toolUse`.
9. Tool-role transcript messages are adapted into Anthropic `tool_result` content blocks.
10. Native structured output maps to `output_config.format`.
11. `.json` requests are normalized to `.jsonSchema(.anyJSON)`.
12. 429 responses parse `retry-after` and `retry-after-ms` correctly.
13. 401 responses map to `.authenticationFailed`.
14. `max_tokens` defaults to 4096 when `maxTokens` is nil.
15. Stream cancellation stops transport work and emits no extra events.
16. `pause_turn` and `refusal` map to distinct `AIFinishReason` cases.
17. Cache usage fields map into `AIUsage.inputTokenDetails`.
18. Custom headers from `AIRequest.headers` are forwarded.
19. `embed(_:)` fails with `AIError.unsupportedFeature` without making a transport call.
20. Interrupted SSE streams surface `AIError.streamInterrupted` after partial output.
21. Published input capabilities include the supported Anthropic image and document MIME types.
22. Compatibility aliases like `.claude(.sonnet4_5)` resolve to the current shipped model IDs.
23. HTTP-date `Retry-After` headers are parsed into `.rateLimited(retryAfter:)`.
24. Malformed text and `tool_use` response blocks fail with `AIError.decodingError` instead of silently synthesizing empty values.
25. SSE `error` events surface mapped `AIError` values instead of `AIError.streamInterrupted`.
26. Malformed `text_delta` payloads fail with `AIError.decodingError` instead of emitting empty text.

## Acceptance Criteria

- [ ] `AnthropicProvider` conforms to `AIProvider` and publishes non-default capabilities.
- [ ] Non-streaming completions work with text, vision, documents, tool use, and native structured output.
- [ ] Streaming works with text deltas, tool-input deltas, usage, and finish reasons.
- [ ] Tool transcript replay is explicitly defined and matches Anthropic's content-block model.
- [ ] Native structured output uses `output_config.format`, with compatibility warnings rather than silent fallback when support is unsupported or unverified.
- [ ] `.json` requests are normalized into schema-backed JSON generation rather than prompt injection by default.
- [ ] All HTTP and transport failures map to `AIError` cases.
- [ ] `AIModel.claude(...)` resolves to current model IDs and still allows `custom(String)`.
- [ ] `max_tokens` defaults to 4096 when not specified.
- [ ] Unsupported model/parameter combinations emit warnings instead of silently dropping fields.
- [ ] Cache token usage is parsed into `AIUsage.inputTokenDetails`.
- [ ] Custom headers and custom transport are supported.
- [ ] Embeddings are explicitly unsupported rather than silently ignored.
- [ ] Input capabilities advertise supported image and document MIME types.
- [ ] Regression coverage includes malformed payload handling, SSE error events, and header-based retry guidance.
